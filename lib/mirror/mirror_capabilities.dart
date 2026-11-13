import 'dart:convert';

import '../core/stickers/wire_codec.dart';

/// Что объявило подключённое зеркало (`GET /api/v1/capabilities`).
/// Чего в ответе нет — того в клиенте нет: адреса и ключи сервисов в
/// сборку не зашиваются, у каждого экземпляра свои.
class MirrorCapabilities {
  const MirrorCapabilities({
    this.name,
    this.contact,
    this.sseUrl,
    this.images,
    this.reports,
    this.stickers,
  });

  /// Зеркало без ответа (старая версия или нет сохранённых настроек) — ничего не умеет.
  static const none = MirrorCapabilities();

  final String? name;

  /// Контакт оператора экземпляра — показываем рядом с жалобой.
  final String? contact;

  /// Полный URL SSE-транспорта (`https://sse.domain.com/sse`).
  final Uri? sseUrl;

  /// Базовый адрес резервного домена SSE для обычных REST-запросов к зеркалу.
  Uri? get sseBaseUrl {
    final u = sseUrl;
    if (u == null) return null;
    return Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
    );
  }

  final ImagesCapability? images;
  final ReportsCapability? reports;
  final StickersCapability? stickers;

  Map<String, Object?> toJson() => {
    'name': name,
    'operator': {'contact': contact},
    if (sseUrl != null) 'sse_url': sseUrl.toString(),
    'images': images == null
        ? null
        : {
            'enabled': true,
            'base_url': images!.baseUrl.toString(),
            'public_key': base64.encode(images!.publicKey),
            'max_bytes': images!.maxBytes,
            'preview_hosts': images!.previewHosts.toList(),
            'report': images!.report,
            'delete': images!.delete,
          },
    'stickers': stickers?.toJson(),
    'reports': reports == null
        ? null
        : {
            'base_url': reports!.baseUrl.toString(),
            'api_key': reports!.apiKey,
            'notices': reports!.notices,
          },
  };

  /// `sse.domain.com` или `https://sse.domain.com` → `https://sse.domain.com/sse`;
  /// если путь указан явно (`https://sse.domain.com/custom/sse`), сохраняется.
  static Uri? parseSseUrl(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty) return null;
    final withScheme = s.contains('://') ? s : 'https://$s';
    final u = Uri.tryParse(withScheme);
    if (u == null || u.scheme.toLowerCase() != 'https' || u.host.isEmpty) {
      return null;
    }
    final path = u.path.isEmpty || u.path == '/' ? '/sse' : u.path;
    return Uri(
      scheme: 'https',
      host: u.host.toLowerCase(),
      port: u.hasPort ? u.port : null,
      path: path,
      queryParameters: u.queryParameters.isEmpty ? null : u.queryParameters,
    );
  }

  static MirrorCapabilities parse(Object? j) {
    if (j is! Map) return none;
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final op = j['operator'];
    return MirrorCapabilities(
      name: str(j['name']),
      contact: op is Map ? str(op['contact']) : null,
      sseUrl: parseSseUrl(j['sse_url']),
      images: ImagesCapability.tryParse(j['images']),
      reports: ReportsCapability.tryParse(j['reports']),
      stickers: StickersCapability.tryParse(j['stickers']),
    );
  }
}

/// Сервис картинок экземпляра.
class ImagesCapability {
  const ImagesCapability({
    required this.baseUrl,
    required this.publicKey,
    required this.maxBytes,
    required this.previewHosts,
    this.report = false,
    this.delete = false,
  });

  final Uri baseUrl;

  /// Публичный ключ сервиса X25519, 32 байта.
  final List<int> publicKey;
  final int maxBytes;

  /// Хосты, с которых показываем превью в ленте (в нижнем регистре).
  final Set<String> previewHosts;
  final bool report;
  final bool delete;

  /// Хост API сервиса: его картинки можно удалить и на них пожаловаться.
  String get host => baseUrl.host.toLowerCase();

  static ImagesCapability? tryParse(Object? j) {
    if (j is! Map || j['enabled'] != true) return null;
    final base = Uri.tryParse(j['base_url'] is String ? j['base_url'] : '');
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      return null;
    }
    List<int> key;
    try {
      key = base64.decode(j['public_key'] as String);
    } catch (_) {
      return null;
    }
    if (key.length != 32) return null;
    final hosts = j['preview_hosts'];
    final max = j['max_bytes'];
    final listed = {
      if (hosts is List)
        for (final h in hosts)
          if (h is String && h.isNotEmpty) h.toLowerCase(),
    };
    return ImagesCapability(
      baseUrl: base.path.endsWith('/')
          ? base
          : base.replace(path: '${base.path}/'),
      publicKey: key,
      maxBytes: max is int && max > 0 ? max : 10 * 1024 * 1024,
      previewHosts: listed.isEmpty ? {base.host.toLowerCase()} : listed,
      report: j['report'] == true,
      delete: j['delete'] == true,
    );
  }
}

/// Сервер отчётов и объявлений, который указал экземпляр.
class ReportsCapability {
  const ReportsCapability({
    required this.baseUrl,
    this.apiKey = '',
    this.notices = false,
  });

  final Uri baseUrl;
  final String apiKey;

  /// Можно ли брать с этого сервера объявления.
  final bool notices;

  static ReportsCapability? tryParse(Object? j) {
    if (j is! Map) return null;
    final base = Uri.tryParse(j['base_url'] is String ? j['base_url'] : '');
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      return null;
    }
    final key = j['api_key'];
    return ReportsCapability(
      baseUrl: base.path.endsWith('/')
          ? base
          : base.replace(path: '${base.path}/'),
      apiKey: key is String ? key : '',
      notices: j['notices'] == true,
    );
  }
}

class StickerSourceAnnouncement {
  const StickerSourceAnnouncement({required this.url, this.label});
  final String url;
  final String? label;
}

class StickerMessageApiCapability {
  const StickerMessageApiCapability({
    required this.history,
    required this.realtime,
  });
  final bool history;
  final bool realtime;
}

/// Independent capability: a source can exist without sticker history support.
class StickersCapability {
  StickersCapability._(
    this.sourceSchemaVersions,
    this.wireVersions,
    this.sources,
    this.messageApi,
  );
  final List<int> sourceSchemaVersions;
  final List<int> wireVersions;
  final List<StickerSourceAnnouncement> sources;
  final StickerMessageApiCapability? messageApi;

  Map<String, Object?> toJson() => {
    'enabled': true,
    'source_schema_versions': sourceSchemaVersions,
    'wire_versions': wireVersions,
    'sources': [
      for (final source in sources)
        {'url': source.url, if (source.label != null) 'label': source.label},
    ],
    if (messageApi != null)
      'message_api': {
        'version': 1,
        'history': messageApi!.history,
        'realtime': messageApi!.realtime,
      },
  };

  static StickersCapability? tryParse(Object? value) {
    if (value is! Map || value['enabled'] != true) return null;
    List<int> versions(Object? v) => v is List
        ? List.unmodifiable(v.whereType<int>().where((n) => n > 0).toSet())
        : const [];
    final schemas = versions(value['source_schema_versions']);
    final wire = versions(value['wire_versions']);
    if (!schemas.contains(1)) return null;
    final raw = value['sources'];
    if (raw is! List || raw.length > 16) return null;
    final sources = <StickerSourceAnnouncement>[];
    final urls = <String>{};
    for (final item in raw) {
      if (item is! Map || item['url'] is! String) continue;
      try {
        final url = normalizeSourceUrl(item['url'] as String);
        if (!urls.add(url)) continue;
        final label = item['label'];
        sources.add(
          StickerSourceAnnouncement(
            url: url,
            label:
                label is String &&
                    label.trim().isNotEmpty &&
                    label.runes.length <= 160 &&
                    !label.runes.any((c) => c < 32 || (c >= 127 && c <= 159))
                ? label
                : null,
          ),
        );
      } on FormatException {
        // A malformed declaration must not disable unrelated services/sources.
      }
    }
    final api = value['message_api'];
    return StickersCapability._(
      schemas,
      wire,
      List.unmodifiable(sources),
      api is Map &&
              api['version'] is int &&
              api['version'] == 1 &&
              api['history'] is bool &&
              api['realtime'] is bool
          ? StickerMessageApiCapability(
              history: api['history'] as bool,
              realtime: api['realtime'] as bool,
            )
          : null,
    );
  }
}
