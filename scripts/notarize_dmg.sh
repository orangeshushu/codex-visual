#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/build/CodexVisual.dmg}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  echo "Run scripts/create_dmg.sh first." >&2
  exit 1
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  /usr/bin/xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  /usr/bin/xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  cat >&2 <<'TEXT'
Missing notarization credentials.

Use either:
  NOTARY_PROFILE=codexvisual-notary scripts/notarize_dmg.sh

or:
  APPLE_ID=you@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx scripts/notarize_dmg.sh

You can create a keychain profile with:
  xcrun notarytool store-credentials codexvisual-notary --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
TEXT
  exit 1
fi

/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

echo "$DMG_PATH"
