#!/usr/bin/env bash
# Генерирует Dart-код из meshtastic/protobufs в lib/core/proto/generated.
# Результат коммитится, поэтому для обычной сборки protoc не нужен.
# Нужны: protoc (brew install protobuf) и `dart pub global activate protoc_plugin`.
set -euo pipefail
cd "$(dirname "$0")/.."

REF="${1:-$(cat tool/protobufs.ref)}"
SRC=.dart_tool/protobufs
OUT=lib/core/proto/generated

rm -rf "$SRC" "$OUT"
git clone --quiet https://github.com/meshtastic/protobufs.git "$SRC"
git -C "$SRC" checkout --quiet "$REF"
echo "$REF" > tool/protobufs.ref

# The client uses a private sticker port in addition to the upstream enum.
perl -pi -e 's/^([ \t]*)(ATAK_FORWARDER[ \t]*=[ \t]*257;)/$1$2\n\n${1}MESHEX_STICKER_APP = 283;/' \
  "$SRC/meshtastic/portnums.proto"
grep -q 'MESHEX_STICKER_APP = 283;' "$SRC/meshtastic/portnums.proto"

mkdir -p "$OUT"
PATH="$HOME/.pub-cache/bin:$PATH" protoc \
  -I "$SRC" \
  --dart_out="$OUT" \
  "$SRC"/meshtastic/*.proto
echo "protobufs @ $(git -C "$SRC" rev-parse --short HEAD) → $OUT"
