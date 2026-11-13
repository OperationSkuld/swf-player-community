#!/usr/bin/env bash
# Download a pinned, reproducible Ruffle self-hosted runtime into Resources/Web.
# Ruffle is MIT OR Apache-2.0 licensed; license texts are bundled when present.
set -euo pipefail

VERSION="${1:-0.7.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/SWFPlayer/Resources/Web"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"
URL="https://registry.npmjs.org/@ruffle-rs/ruffle/-/ruffle-${VERSION}.tgz"

echo "==> Fetching Ruffle ${VERSION}"
echo "    ${URL}"
curl -fsSL --retry 3 --retry-delay 2 "$URL" -o "$TMP/ruffle.tgz"
tar -xzf "$TMP/ruffle.tgz" -C "$TMP"

PKG="$TMP/package"
if [ ! -f "$PKG/ruffle.js" ]; then
  echo "::error::ruffle.js not found inside the npm tarball"
  exit 1
fi

# Drop runtime files from any previous version so stale hashed bundles do not linger.
find "$DEST" -type f \( -name '*.js' -o -name '*.js.map' -o -name '*.wasm' \) -exec rm -f {} +

# Copy recursively: some releases move the WASM/core chunks into a subdirectory.
find "$PKG" -type f \( -name '*.js' -o -name '*.js.map' -o -name '*.wasm' \) -exec cp {} "$DEST/" \;

# Licenses are informational; a renamed/missing file must not fail the build.
for lic in LICENSE_MIT LICENSE_APACHE; do
  if [ -f "$PKG/$lic" ]; then
    cp "$PKG/$lic" "$DEST/"
  else
    echo "::warning::${lic} not present in Ruffle ${VERSION}; skipping"
  fi
done

printf '%s\n' "$VERSION" > "$DEST/RUFFLE_VERSION"

JS_COUNT=0
for file in "$DEST"/*.js; do
  if [ -f "$file" ]; then JS_COUNT=$((JS_COUNT + 1)); fi
done
WASM_COUNT=0
for file in "$DEST"/*.wasm; do
  if [ -f "$file" ]; then WASM_COUNT=$((WASM_COUNT + 1)); fi
done
if [ "$WASM_COUNT" -lt 1 ] || [ "$JS_COUNT" -lt 1 ]; then
  echo "::error::Ruffle runtime looks incomplete (js=$JS_COUNT wasm=$WASM_COUNT)"
  exit 1
fi

echo "==> Bundled ${JS_COUNT} JS + ${WASM_COUNT} WASM files into ${DEST}"
ls -lh "$DEST"
