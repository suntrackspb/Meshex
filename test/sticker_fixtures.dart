import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshex/data/stickers/sticker_http.dart';

const testSourceUrl = 'https://s.example/stickers/source.json';
const testPackHash =
    'd2431a467ff3f617bf814ee3b2fddb976eba91ecbfe9a08650e84bd2cb5817d3';
Uint8List stickerFixture(String name) =>
    File('test/fixtures/stickers/$name').readAsBytesSync();
Future<String> stickerDigest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class StickerFetchCall {
  const StickerFetchCall(this.url, this.etag, this.limit, this.contentType);
  final Uri url;
  final String? etag;
  final int limit;
  final String contentType;
}

class TestStickerHttp implements StickerHttp {
  final bodies = <Uri, Uint8List>{};
  final status = <Uri, int>{};
  final etags = <Uri, String>{};
  final calls = <StickerFetchCall>[];
  Future<void> Function(Uri)? beforeFetch;

  TestStickerHttp() {
    addSource(testSourceUrl);
  }

  void addSource(
    String url, {
    Uint8List? manifest,
    String hash = testPackHash,
  }) {
    final source = Uri.parse(url);
    final descriptor =
        (jsonDecode(utf8.decode(stickerFixture('source.json'))) as Map)
          ..['canonical_url'] = url;
    bodies[source] = Uint8List.fromList(utf8.encode(jsonEncode(descriptor)));
    bodies[source.resolve('catalog.json')] = hash == testPackHash
        ? stickerFixture('catalog.json')
        : Uint8List.fromList(
            utf8.encode(
              '{"schema":"meshex.stickers.catalog","version":1,"packs":[]}',
            ),
          );
    bodies[source.resolve('packs/$hash/manifest.json')] =
        manifest ?? stickerFixture('manifest.json');
    for (final file in Directory(
      'test/fixtures/stickers/media',
    ).listSync().whereType<File>()) {
      bodies[source.resolve(
        'packs/$hash/media/${file.uri.pathSegments.last}',
      )] = file
          .readAsBytesSync();
    }
  }

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
    cancellation?.check();
    calls.add(StickerFetchCall(url, etag, limit, contentType));
    final wait = beforeFetch?.call(url);
    if (wait != null) {
      if (cancellation == null) {
        await wait;
      } else {
        await cancellation.run(wait);
      }
    }
    cancellation?.check();
    final code = status[url] ?? (bodies.containsKey(url) ? 200 : 404);
    if (code == 304)
      return StickerHttpResponse(
        Uint8List(0),
        etag: etags[url] ?? etag,
        notModified: true,
      );
    if (code != 200) throw StickerHttpException(code);
    final bytes = bodies[url]!;
    if (bytes.length > limit)
      throw const FormatException('Sticker response too large');
    return StickerHttpResponse(Uint8List.fromList(bytes), etag: etags[url]);
  }
}
