#!/usr/bin/env bash
# Wrap the unsigned .app into a standard IPA (Payload/SWFPlayer.app).
# No signing identity, no provisioning profile, no entitlements.
set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "::error::unsigned .app not found: ${APP:-<empty>}"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

rm -rf staging SWFPlayer-unsigned.ipa
mkdir -p staging/Payload
cp -R "$APP" staging/Payload/SWFPlayer.app

# Defensive: make sure the artifact really is unsigned.
/usr/bin/codesign --remove-signature staging/Payload/SWFPlayer.app 2>/dev/null || true
rm -rf staging/Payload/SWFPlayer.app/_CodeSignature
/usr/bin/find staging -name '.DS_Store' -exec /bin/rm -f {} + 2>/dev/null || true
/usr/bin/xattr -cr staging 2>/dev/null || true

(cd staging && /usr/bin/zip -qry ../SWFPlayer-unsigned.ipa Payload -x '*.DS_Store')

echo "==> Created ${ROOT}/SWFPlayer-unsigned.ipa"
ls -lh SWFPlayer-unsigned.ipa
