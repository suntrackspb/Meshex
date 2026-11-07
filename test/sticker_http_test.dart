import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/stickers/sticker_http.dart';

import 'sticker_fixtures.dart';

class _Headers extends Fake implements HttpHeaders {
  final values = <String, String>{};
  ContentType? mime;
  @override
  ContentType? get contentType => mime;
  @override
  String? value(String name) => values[name];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = '$value';
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.headers, this.chunks);
  @override
  final int statusCode;
  @override
  final _Headers headers;
  final List<List<int>> chunks;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final _Headers headers = _Headers();
  bool? redirects;
  @override
  set followRedirects(bool value) {
    redirects = value;
  }

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.request);
  final _Request request;
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? factory;
  bool checkDns = false;
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  set findProxy(String Function(Uri)? value) {
    expect(value!(Uri.parse(testSourceUrl)), 'DIRECT');
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) {
    factory = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (checkDns) await factory!(url, null, null);
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  test(
    'deny non-public destinations, including metadata, mapped IPv4 and IPv6 tunnels',
    () {
      for (final address in [
        '0.0.0.0',
        '10.1.2.3',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.169.254',
        '172.16.0.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.18.0.1',
        '224.0.0.1',
        '255.255.255.255',
        '::',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        'ff02::1',
        '2001:db8::1',
        '2002:7f00:1::1',
      ]) {
        expect(
          isPublicStickerAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
      for (final address in ['8.8.8.8', '1.1.1.1', '2606:4700:4700::1111']) {
        expect(
          isPublicStickerAddress(InternetAddress(address)),
          isTrue,
          reason: address,
        );
      }
    },
  );

  test('same-origin source prefix and credentials policy is strict', () {
    for (final url in [
      'http://s.example/stickers/source.json',
      'https://other.example/stickers/source.json',
      'https://s.example:444/stickers/source.json',
      'https://u:p@s.example/stickers/source.json',
      'https://s.example/stickers/source.json?q=a',
      'https://s.example/stickers/source.json#x',
      'https://s.example/elsewhere/image.webp',
    ]) {
      expect(
        () => validateStickerFetchUrl(Uri.parse(url), testSourceUrl),
        throwsFormatException,
      );
    }
  });

  Future<void> withClient(_Client client, Future<void> Function() callback) =>
      HttpOverrides.runZoned(callback, createHttpClient: (_) => client);
  _Client response(int code, String type, List<List<int>> chunks) => _Client(
    _Request(
      _Response(code, _Headers()..mime = ContentType.parse(type), chunks),
    ),
  );

  test(
    'native request forbids redirects, credentials and oversized decoded streams',
    () async {
      for (final code in [301, 302, 307, 410]) {
        final c = response(code, 'application/json', []);
        await withClient(c, () async {
          await expectLater(
            NativeStickerHttp().fetch(
              Uri.parse(testSourceUrl),
              sourceUrl: testSourceUrl,
              limit: 10,
              contentType: 'application/json',
            ),
            throwsA(isA<StickerHttpException>()),
          );
        });
        expect(c.request.redirects, isFalse);
        expect(c.closed, isTrue);
        expect(c.request.headers.values.keys, isNot(contains('authorization')));
        expect(c.request.headers.values.keys, isNot(contains('cookie')));
      }
      final c = response(200, 'application/json', [
        [1, 2],
        [3, 4],
      ]);
      await withClient(c, () async {
        await expectLater(
          NativeStickerHttp().fetch(
            Uri.parse(testSourceUrl),
            sourceUrl: testSourceUrl,
            limit: 3,
            contentType: 'application/json',
          ),
          throwsFormatException,
        );
      });
    },
  );

  test(
    'MIME is enforced; conditional fetch accepts 304 only when requested',
    () async {
      final bad = response(200, 'text/html', []);
      await withClient(bad, () async {
        await expectLater(
          NativeStickerHttp().fetch(
            Uri.parse(testSourceUrl),
            sourceUrl: testSourceUrl,
            limit: 10,
            contentType: 'application/json',
          ),
          throwsFormatException,
        );
      });
      final c = response(304, 'application/json', []);
      await withClient(c, () async {
        final r = await NativeStickerHttp().fetch(
          Uri.parse(testSourceUrl),
          sourceUrl: testSourceUrl,
          limit: 10,
          contentType: 'application/json',
          etag: '"v1"',
        );
        expect(r.notModified, isTrue);
        expect(c.request.headers.values['if-none-match'], '"v1"');
      });
    },
  );

  test(
    'DNS containing a private address is rejected before any connection',
    () async {
      final c = response(200, 'application/json', [])..checkDns = true;
      await withClient(c, () async {
        final http = NativeStickerHttp(
          lookup: (_) async => [
            InternetAddress('8.8.8.8'),
            InternetAddress('127.0.0.1'),
          ],
        );
        await expectLater(
          http.fetch(
            Uri.parse(testSourceUrl),
            sourceUrl: testSourceUrl,
            limit: 10,
            contentType: 'application/json',
          ),
          throwsA(isA<SocketException>()),
        );
      });
      expect(c.closed, isTrue);
    },
  );

  test('cancellation ends pending DNS and closes client', () async {
    final c = response(200, 'application/json', [])..checkDns = true;
    final token = StickerCancellation();
    final resolving = Completer<List<InternetAddress>>();
    await withClient(c, () async {
      final http = NativeStickerHttp(lookup: (_) => resolving.future);
      final request = http.fetch(
        Uri.parse(testSourceUrl),
        sourceUrl: testSourceUrl,
        limit: 10,
        contentType: 'application/json',
        cancellation: token,
      );
      final result = expectLater(request, throwsA(isA<StickerCancelled>()));
      token.cancel();
      await result;
      expect(c.closed, isTrue);
      resolving.complete([InternetAddress('127.0.0.1')]);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
