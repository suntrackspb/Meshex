import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/stickers/wire_codec.dart';

class StickerCancelled implements Exception {
  const StickerCancelled();
}

class StickerCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const StickerCancelled();
  }

  Future<T> run<T>(Future<T> operation) {
    check();
    return Future.any([
      operation,
      _cancelled.future.then<T>((_) => throw const StickerCancelled()),
    ]);
  }
}

class StickerHttpException implements Exception {
  const StickerHttpException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'HTTP $statusCode';
}

class StickerHttpResponse {
  const StickerHttpResponse(this.bytes, {this.etag, this.notModified = false});
  final Uint8List bytes;
  final String? etag;
  final bool notModified;
}

/// Only the native implementation performs network access. Test transports can
/// replace this interface without disabling address validation in production.
abstract interface class StickerHttp {
  Future<StickerHttpResponse> fetch(
    Uri url, {
    required String sourceUrl,
    required int limit,
    required String contentType,
    String? etag,
    StickerCancellation? cancellation,
  });
}

bool isPublicStickerAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 &&
            (b[1] == 168 || (b[1] == 0 && (b[2] == 0 || b[2] == 2)))) ||
        (b[0] == 198 &&
            (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
        (b[0] == 203 && b[1] == 0 && b[2] == 113)) {
      return false;
    }
    return true;
  }
  // Allow global unicast only. This also excludes mapped IPv4, ULA, loopback,
  // link-local, multicast, translation, and unspecified addresses.
  return b.length == 16 &&
      (b[0] & 0xe0) == 0x20 &&
      !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) &&
      !(b[0] == 0x20 && b[1] == 0x01 && b[2] < 2) && // special-purpose /23
      !(b[0] == 0x20 && b[1] == 0x02); // 6to4
}

void validateStickerFetchUrl(Uri url, String sourceUrl) {
  final source = validateSourceUrl(sourceUrl);
  final prefix = source.resolve('.').path;
  if (url.scheme != 'https' ||
      url.host != source.host ||
      url.port != 443 ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      !url.path.startsWith(prefix) ||
      url.toString().contains('%') ||
      !RegExp(r'^/[A-Za-z0-9._~/-]+$').hasMatch(url.path) ||
      url.path.split('/').any((s) => s == '.' || s == '..')) {
    throw const FormatException('Invalid sticker fetch URL');
  }
}

class NativeStickerHttp implements StickerHttp {
  NativeStickerHttp({Future<List<InternetAddress>> Function(String)? lookup})
    : _lookup = lookup ?? InternetAddress.lookup;
  final Future<List<InternetAddress>> Function(String) _lookup;

  @override
  Future<StickerHttpResponse> fetch(
    Uri url, {
    required String sourceUrl,
    required int limit,
    required String contentType,
    String? etag,
    StickerCancellation? cancellation,
  }) async {
    validateStickerFetchUrl(url, sourceUrl);
    if (limit <= 0 ||
        (etag != null &&
            (etag.length > 1024 ||
                etag.runes.any((c) => c < 32 || c == 127)))) {
      throw const FormatException('Invalid sticker request');
    }
    cancellation?.check();
    final cancel = StickerCancellation();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      cancel.check();
      final addresses = await cancel.run(
        _lookup(uri.host).timeout(const Duration(seconds: 20)),
      );
      if (addresses.isEmpty ||
          addresses.any((a) => !isPublicStickerAddress(a))) {
        throw const SocketException('Sticker source has a non-public address');
      }
      cancel.check();
      // Connect to the checked IP, not the hostname: no second DNS lookup.
      // A custom connectionFactory must also establish TLS explicitly.
      ConnectionTask<Socket>? active;
      Socket? connected;
      void closeConnection() {
        active?.cancel();
        connected?.destroy();
      }

      unawaited(cancel._cancelled.future.then((_) => closeConnection()));
      Future<Socket> connect() async {
        for (var i = 0; i < addresses.length; i++) {
          cancel.check();
          final address = addresses[i];
          try {
            active = await Socket.startConnect(address, 443);
            final socket = await active!.socket.timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                active?.cancel();
                throw const SocketException('Sticker connection timed out');
              },
            );
            connected = socket;
            if (cancel.isCancelled) {
              socket.destroy();
              throw const StickerCancelled();
            }
            if (!isPublicStickerAddress(socket.remoteAddress) ||
                socket.remoteAddress.address != address.address) {
              socket.destroy();
              throw StateError('Sticker connection address mismatch');
            }
            // Preserve SNI and certificate hostname verification without
            // resolving the hostname again or bypassing certificate checks.
            final secure = await SecureSocket.secure(socket, host: uri.host)
                .timeout(
                  const Duration(seconds: 20),
                  onTimeout: () {
                    socket.destroy();
                    throw const SocketException(
                      'Sticker TLS handshake timed out',
                    );
                  },
                );
            connected = secure;
            if (cancel.isCancelled) {
              secure.destroy();
              throw const StickerCancelled();
            }
            return secure;
          } on SocketException {
            connected?.destroy();
            if (i == addresses.length - 1) rethrow;
          } catch (_) {
            connected?.destroy();
            rethrow;
          }
        }
        throw const SocketException('No sticker connection available');
      }

      return ConnectionTask.fromSocket(connect(), closeConnection);
    };
    Future<StickerHttpResponse> read() async {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, contentType);
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close();
      final nextEtag = response.headers.value(HttpHeaders.etagHeader);
      if (response.statusCode == 304 && etag != null) {
        return StickerHttpResponse(
          Uint8List(0),
          etag: nextEtag ?? etag,
          notModified: true,
        );
      }
      if (response.statusCode != 200) {
        throw StickerHttpException(response.statusCode);
      }
      if (response.headers.contentType?.mimeType != contentType) {
        throw const FormatException('Unexpected sticker content type');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancel.check();
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Sticker response too large');
        }
        bytes.add(chunk);
      }
      return StickerHttpResponse(bytes.takeBytes(), etag: nextEtag);
    }

    try {
      final operation = cancel.run(read().timeout(const Duration(seconds: 45)));
      return cancellation == null
          ? await operation
          : await cancellation.run(operation);
    } finally {
      cancel.cancel();
      client.close(force: true);
    }
  }
}
