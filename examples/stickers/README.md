# Public sticker source (STK-DRAFT-2)

Packs are not included in the application. To build a local demo source from the
original test media, run from the client root:

```sh
python3 tool/export_sticker_catalog.py \
  --pack-dir test/fixtures/stickers \
  --source-url https://s.example/stickers/source.json \
  --name 'Demo sticker source' \
  --operator-name 'Demo operator' \
  --operator-contact mailto:operator@example.org \
  --published-at 2026-11-06T00:00:00Z \
  --output /tmp/meshex-sticker-source
```

Output must not exist. Nothing is uploaded. Each input directory contains the
new `manifest.json` and `media/<sha256>.(webp|png)` structure. The prototype's
flat catalog and prepared-pack format are not supported. Exact manifest bytes
are preserved; changing whitespace changes the revision hash.

Serve the output on a public HTTPS hostname without authentication or redirects,
with JSON/WebP/PNG MIME types, `X-Content-Type-Options: nosniff`, and CORS headers
as specified in the shared contract. Descriptor/catalog use ETags and a short
cache lifetime; `packs/<hash>/` is immutable. Source settings accept the public
`source.json` URL. Production publishers must publish atomically and retain old
immutable revisions; this local export tool does not modify an existing source.
