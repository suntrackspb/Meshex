# STK-DRAFT-2 fixtures

These files freeze the exact example in `DOC/STICKERS_CLIENT_PLAN.md` and
`DOC/STICKERS_MIRROR_PLAN.md`. They are test assets, not bundled sticker packs
or a production source. The blue/red solid-color media were created for tests;
the demo manifest declares CC0-1.0.

- `source.json`, `catalog.json`: descriptor and revision index, schema version 1.
- `manifest.json`: exact UTF-8 bytes (1050 bytes, including final LF).
- `media/`: original static WebP, animated WebP and static PNG preview.
- `wire.json`: expected fields, full payload hex and length (81 bytes).

Manifest SHA-256:
`d2431a467ff3f617bf814ee3b2fddb976eba91ecbfe9a08650e84bd2cb5817d3`.
When serving a fixture source, put manifest and media under
`packs/<manifest SHA-256>/`, relative to source.json. Do not reserialize the
manifest: its exact bytes define the revision.

Run `flutter test test/sticker_wire_codec_test.dart test/sticker_message_test.dart`.
This verifies the Dart codec and manifest against the shared vector. Python/TS
implementations and the mirror must use these same bytes; their interoperability
and physical-radio budgets remain separate acceptance work. The codec does no
DNS or HTTP; public-address enforcement on actual connections belongs to the
future source fetcher. ASCII URL normalization is provided; Unicode host input
still requires IDNA conversion in the source input layer.
