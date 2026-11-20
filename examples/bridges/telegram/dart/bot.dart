import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'protocol.dart';

bool validTelegramBotToken(String value) =>
    RegExp(r'^\d+:[A-Za-z0-9_-]{20,}$').hasMatch(value);

typedef TelegramOwner = ({int user, int chat});

typedef TelegramRequest =
    Future<Object?> Function(
      String method,
      BridgeJson params,
      Duration timeout,
    );

class TelegramBot {
  TelegramBot(
    this.token, {
    required TelegramOwner? owner,
    required this.onPairingChanged,
    TelegramRequest? requestApi,
  }) : _owner = owner,
       _requestApi = requestApi;

  final String token;
  final void Function() onPairingChanged;
  final TelegramRequest? _requestApi;
  final _client = HttpClient();
  final _pairCode = _newPairCode();

  static String _newPairCode() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
  }

  final _replies = <int, ({String nodeId, String ref, bool channel})>{};
  final _targets = <String, ({String nodeId, String targetId})>{};
  TelegramOwner? _owner;
  TelegramOwner? candidate;
  String? _username;
  BridgeRequest? _request;
  bool _closed = false;

  String? get username => _username;
  TelegramOwner? get owner => _owner;
  Uri? get pairingUrl => _owner == null && _username != null
      ? Uri.https('t.me', '/$_username', {'start': _pairCode})
      : null;

  void pair(TelegramOwner choice) {
    if (candidate != choice || _closed) return;
    _owner = choice;
    candidate = null;
    onPairingChanged();
  }

  Future<void> open(BridgeRequest request, void Function() onDisconnect) async {
    if (!validTelegramBotToken(token)) {
      throw const BridgeError(-32000, 'Invalid BotFather token');
    }
    final bot = bridgeObject(await _api('getMe', {}));
    final username = bot['username'];
    if (username is! String ||
        !RegExp(r'^[A-Za-z0-9_]{1,64}$').hasMatch(username)) {
      throw const BridgeError(-32000, 'Invalid Telegram bot name');
    }
    final webhook = bridgeObject(await _api('getWebhookInfo', {}));
    if ((webhook['url'] as String?)?.isNotEmpty == true) {
      throw const BridgeError(-32000, 'This bot already has a webhook');
    }
    if (_closed) return;
    _username = username;
    _request = request;
    // Ignore old commands accumulated while Meshex was stopped.
    final startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    unawaited(_poll(request, onDisconnect, startedAt));
  }

  Future<void> _poll(
    BridgeRequest request,
    void Function() disconnect,
    int startedAt,
  ) async {
    int? offset;
    var failures = 0;
    while (!_closed) {
      try {
        final updates =
            await _api('getUpdates', {
                  'timeout': 20,
                  'allowed_updates': ['message'],
                  'offset': ?offset,
                }, timeout: const Duration(seconds: 28))
                as List;
        if (_closed) return;
        failures = 0;
        for (final item in updates.whereType<BridgeJson>()) {
          if (_closed) return;
          final id = item['update_id'];
          if (id is! int) continue;
          final message = item['message'];
          if (message is BridgeJson &&
              message['date'] is int &&
              (message['date'] as int) >= startedAt) {
            await _onMessage(message, id, request);
          }
          offset = id + 1;
        }
      } on TelegramError catch (error) {
        if (_closed) return;
        if (error.code == 401 || error.code == 409) {
          disconnect();
          return;
        }
        final retry = error.retryAfter;
        if (retry != null && retry <= 30) {
          await Future<void>.delayed(Duration(seconds: retry));
          continue;
        }
        failures++;
      } catch (_) {
        if (_closed) return;
        failures++;
      }
      if (failures >= 4) {
        disconnect();
        return;
      }
      if (failures != 0) {
        await Future<void>.delayed(Duration(seconds: failures));
      }
    }
  }

  Future<void> _onMessage(
    BridgeJson message,
    int update,
    BridgeRequest request,
  ) async {
    final chat = message['chat'];
    final sender = message['from'];
    final text = message['text'];
    if (chat is! BridgeJson ||
        sender is! BridgeJson ||
        text is! String ||
        chat['type'] != 'private' ||
        sender['id'] is! int ||
        chat['id'] is! int) {
      return;
    }
    final candidateOwner = (user: sender['id'] as int, chat: chat['id'] as int);
    if (_owner == null) {
      if (candidate == null && text == '/start $_pairCode') {
        candidate = candidateOwner;
        try {
          await _sendText(
            candidateOwner.chat,
            'Your Telegram account ID is ${candidateOwner.user}. Confirm it in the module terminal.',
          );
        } on TelegramError catch (_) {
          // The setup terminal can still show the candidate ID.
        }
        if (!_closed) onPairingChanged();
      }
      return;
    }
    if (candidateOwner != _owner) return;
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return;
    final command = parts.first;
    final args = text.trim().substring(command.length).trimLeft();
    try {
      if (command == '/start' || command == '/help') {
        await _sendText(
          candidateOwner.chat,
          'Reply to a mesh message to answer it.\n'
          '/targets [search] lists destinations\n'
          '/send <number> <text> starts a new message\n'
          '/mention <text> mentions the author when replying in a channel\n'
          '/react <emoji> reacts to the mesh message you reply to',
        );
        return;
      }
      if (command == '/targets') {
        final response = await request('mesh.listTargets', {
          if (args.isNotEmpty) 'query': args,
        });
        final nodeId = response['nodeId'] as String;
        final targets = (response['targets'] as List)
            .whereType<BridgeJson>()
            .take(25);
        final lines = <String>[];
        for (final target in targets) {
          final id = target['id'] as String;
          final destination = (nodeId: nodeId, targetId: id);
          final number =
              _targets.entries
                  .where((entry) => entry.value == destination)
                  .firstOrNull
                  ?.key ??
              '${_targets.length + 1}';
          _targets[number] = destination;
          final name = (target['name'] as String).replaceAll(
            RegExp(r'[\r\n]'),
            ' ',
          );
          lines.add(
            '$number. ${target['kind'] == 'channel' ? '#' : ''}$name'
            '${id.startsWith('dm:') ? ' (${id.substring(3)})' : ''}',
          );
        }
        await _sendText(
          candidateOwner.chat,
          lines.isEmpty ? 'No matching destinations.' : lines.join('\n'),
        );
        return;
      }
      final params = <String, dynamic>{'commandId': 'telegram:$update'};
      if (command == '/send') {
        final separator = args.indexOf(RegExp(r'\s'));
        final choice = separator < 0
            ? null
            : _targets[args.substring(0, separator)];
        if (choice == null) {
          await _sendText(
            candidateOwner.chat,
            'Run /targets, then /send <number> <text>.',
          );
          return;
        }
        params.addAll({
          'nodeId': choice.nodeId,
          'targetId': choice.targetId,
          'text': args.substring(separator).trimLeft(),
        });
      } else {
        final parent = message['reply_to_message'];
        final reply = parent is BridgeJson
            ? _replies[parent['message_id']]
            : null;
        if (reply == null ||
            (command.startsWith('/') &&
                command != '/mention' &&
                command != '/react')) {
          await _sendText(
            candidateOwner.chat,
            'Reply to a recent mesh message or open /help.',
          );
          return;
        }
        if (command == '/mention' && !reply.channel) {
          await _sendText(
            candidateOwner.chat,
            'Use /mention in a reply to a channel message.',
          );
          return;
        }
        params.addAll({
          'nodeId': reply.nodeId,
          'replyRef': reply.ref,
          'text': command == '/mention' || command == '/react' ? args : text,
          if (command == '/mention') 'mentionAuthor': true,
          if (command == '/react') 'reaction': true,
        });
      }
      final result = await request('mesh.sendMessage', params);
      final response = result['status'] == 'queued'
          ? 'Queued for mesh delivery.'
          : 'Previous send result is unknown.';
      await _sendText(candidateOwner.chat, response);
    } on BridgeError catch (e) {
      await _sendText(candidateOwner.chat, e.message);
    }
  }

  Future<void> publish(String method, BridgeJson params) async {
    final owner = _owner;
    if (_closed || owner == null) return;
    if (const {
      'mesh.messageReceived',
      'mesh.reactionReceived',
      'mesh.stickerReceived',
    }.contains(method)) {
      final author = bridgeObject(params['author']);
      final target = bridgeObject(params['target']);
      final channel = target['kind'] == 'channel';
      final label = channel ? '#${target['name']}' : 'DM';
      final sender = '$label · ${author['name']} (${author['id']})';
      if (method == 'mesh.reactionReceived') {
        final original = params['originalRef'];
        final parent = _replies.entries
            .where((e) => e.value.ref == original)
            .lastOrNull
            ?.key;
        final packet = (params['radio'] as BridgeJson?)?['replyId'];
        final reaction = 'Reaction ${params['emoji']}';
        await _sendText(
          owner.chat,
          '$sender\n$reaction${parent == null ? ' to packet $packet' : ''}',
          replyTo: parent,
        );
        return;
      }

      void remember(int id) {
        if (_closed) return;
        if (_replies.length >= 512) _replies.remove(_replies.keys.first);
        _replies[id] = (
          nodeId: params['nodeId'] as String,
          ref: params['replyRef'] as String,
          channel: channel,
        );
      }

      if (method == 'mesh.stickerReceived') {
        final sticker = bridgeObject(params['sticker']);
        final pack = sticker['pack_sha256'] as String;
        final identity = '${pack.substring(0, 12)}/${sticker['sticker_id']}';
        ({Uint8List bytes, bool animated})? media;
        try {
          media = await _stickerMedia(params['replyRef'] as String);
        } on BridgeError {
          // Sticker identity still helps identify an unavailable pack.
        } on FormatException {
          // An incomplete media transfer is handled the same way.
        }
        final suffix = media == null ? ' · media unavailable' : '';
        final header = await _sendText(
          owner.chat,
          '$sender\nSticker $identity$suffix',
        );
        remember(header);
        if (media == null || _closed) return;
        final file = await _sendSticker(
          owner.chat,
          media.bytes,
          animated: media.animated,
          replyTo: header,
        );
        remember(file);
      } else {
        final id = await _sendText(owner.chat, '$sender\n${params['text']}');
        remember(id);
      }
    } else if (method == 'mesh.deliveryChanged') {
      final status = params['status'];
      final text = switch (status) {
        'acked' when params['ackProof'] == 'ACK_PROOF_VALID' =>
          'Recipient confirmed delivery.',
        'acked' when params['ackProof'] == 'ACK_PROOF_INVALID' =>
          'Mesh acknowledgement could not be verified.',
        'acked' => 'Mesh acknowledged the packet.',
        'timeout' => 'Mesh delivery was not confirmed.',
        'unknown' => 'Mesh delivery status is unknown.',
        _ => 'Mesh send failed (${params['error'] ?? status}).',
      };
      await _sendText(owner.chat, text);
    }
  }

  Future<({Uint8List bytes, bool animated})?> _stickerMedia(
    String reference,
  ) async {
    final request = _request;
    if (request == null) return null;
    final bytes = BytesBuilder(copy: false);
    int? size;
    var animated = false;
    while (size == null || bytes.length < size) {
      final result = await request('mesh.getStickerMedia', {
        'replyRef': reference,
        'offset': bytes.length,
      });
      final length = result['size'];
      final encoded = result['dataBase64'];
      if (length is! int ||
          length < 1 ||
          length > 5 * 1024 * 1024 ||
          encoded is! String ||
          (size != null && length != size)) {
        throw const FormatException('Invalid sticker media');
      }
      size ??= length;
      animated = result['animated'] == true;
      final chunk = base64Decode(encoded);
      if (chunk.isEmpty || bytes.length + chunk.length > size) {
        throw const FormatException('Invalid sticker media chunk');
      }
      bytes.add(chunk);
    }
    return (bytes: bytes.takeBytes(), animated: animated);
  }

  Future<int> _sendSticker(
    int chat,
    Uint8List bytes, {
    required bool animated,
    required int replyTo,
  }) => _queueWrite(() async {
    final params = <String, dynamic>{
      'chat_id': chat,
      'reply_parameters': {
        'message_id': replyTo,
        'allow_sending_without_reply': true,
      },
    };
    if (!animated) {
      try {
        final result = bridgeObject(
          await _api(
            'sendSticker',
            params,
            upload: (field: 'sticker', bytes: bytes),
          ),
        );
        return result['message_id'] as int;
      } on TelegramError catch (error) {
        if (error.code != 400) rethrow;
      }
    }
    final result = bridgeObject(
      await _api(
        'sendDocument',
        params,
        upload: (field: 'document', bytes: bytes),
      ),
    );
    return result['message_id'] as int;
  });

  // Serialize writes to the bot chat, including the few sent during pairing.
  Future<void> _writeTail = Future.value();

  Future<int> _sendText(int chat, String text, {int? replyTo}) =>
      _queueWrite(() => _sendTextNow(chat, text, replyTo));

  Future<int> _queueWrite(Future<int> Function() sendMessage) {
    final send = _writeTail.then((_) => sendMessage());
    _writeTail = send.then<void>((_) {}, onError: (Object _) {});
    return send;
  }

  Future<int> _sendTextNow(int chat, String text, int? replyTo) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final result = bridgeObject(
          await _api('sendMessage', {
            'chat_id': chat,
            'text': text,
            if (replyTo != null)
              'reply_parameters': {
                'message_id': replyTo,
                'allow_sending_without_reply': true,
              },
            'link_preview_options': {'is_disabled': true},
          }),
        );
        return result['message_id'] as int;
      } on TelegramError catch (error) {
        final retry = error.retryAfter;
        if (_closed || attempt >= 2 || retry == null || retry > 30) rethrow;
        await Future<void>.delayed(Duration(seconds: retry));
      }
    }
  }

  Future<Object?> _api(
    String method,
    BridgeJson params, {
    Duration timeout = const Duration(seconds: 10),
    ({String field, Uint8List bytes})? upload,
  }) async {
    if (_closed) throw const TelegramError(0);
    try {
      final requestApi = _requestApi;
      if (requestApi != null) return await requestApi(method, params, timeout);
      final request = await _client
          .postUrl(Uri.https('api.telegram.org', '/bot$token/$method'))
          .timeout(timeout);
      request.followRedirects = false;
      final List<int> data;
      if (upload == null) {
        request.headers.contentType = ContentType.json;
        data = utf8.encode(jsonEncode(params));
      } else {
        final boundary = _newPairCode();
        request.headers.contentType = ContentType(
          'multipart',
          'form-data',
          parameters: {'boundary': boundary},
        );
        final body = BytesBuilder(copy: false);
        for (final entry in params.entries) {
          final value = entry.value is String
              ? entry.value
              : jsonEncode(entry.value);
          body.add(
            utf8.encode(
              '--$boundary\r\nContent-Disposition: form-data; '
              'name="${entry.key}"\r\n\r\n$value\r\n',
            ),
          );
        }
        body.add(
          utf8.encode(
            '--$boundary\r\nContent-Disposition: form-data; '
            'name="${upload.field}"; filename="sticker.webp"\r\n'
            'Content-Type: image/webp\r\n\r\n',
          ),
        );
        body.add(upload.bytes);
        body.add(utf8.encode('\r\n--$boundary--\r\n'));
        data = body.takeBytes();
      }
      request.contentLength = data.length;
      request.add(data);
      final response = await request.close().timeout(timeout);
      final body = bridgeObject(
        jsonDecode(await utf8.decoder.bind(response).join().timeout(timeout)),
      );
      if (body['ok'] != true) {
        final parameters = body['parameters'];
        final delay = parameters is BridgeJson
            ? parameters['retry_after']
            : null;
        throw TelegramError(
          body['error_code'] as int? ?? response.statusCode,
          retryAfter: delay is int && delay >= 0 ? delay : null,
        );
      }
      return body['result'];
    } on TelegramError {
      rethrow;
    } catch (_) {
      // HTTP exceptions may include the request URL, which contains the token.
      throw const TelegramError(0);
    }
  }

  void close() {
    _closed = true;
    _replies.clear();
    _targets.clear();
    _client.close(force: true);
  }
}

class TelegramError implements Exception {
  const TelegramError(this.code, {this.retryAfter});
  final int code;
  final int? retryAfter;

  @override
  String toString() => switch (code) {
    0 => 'Could not connect to the Telegram Bot API.',
    401 => 'Telegram rejected the bot token.',
    409 => 'Another process is receiving updates for this Telegram bot.',
    _ => 'Telegram Bot API error ($code).',
  };
}
