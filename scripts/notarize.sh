#!/usr/bin/env bash
set -euo pipefail

# Notarize and staple a DMG (or .app).
# Required env:
#   APP_STORE_CONNECT_API_KEY_ID
#   APP_STORE_CONNECT_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY_P8  (PEM contents or path to .p8)

ARTIFACT="${1:-}"
if [[ -z "$ARTIFACT" || ! -e "$ARTIFACT" ]]; then
  echo "usage: $0 <path-to-dmg-or-app>" >&2
  exit 1
fi

: "${APP_STORE_CONNECT_API_KEY_ID:?Set APP_STORE_CONNECT_API_KEY_ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Set APP_STORE_CONNECT_ISSUER_ID}"
: "${APP_STORE_CONNECT_API_KEY_P8:?Set APP_STORE_CONNECT_API_KEY_P8}"

KEY_PATH=""
CLEANUP_KEY=0
if [[ -f "$APP_STORE_CONNECT_API_KEY_P8" ]]; then
  KEY_PATH="$APP_STORE_CONNECT_API_KEY_P8"
else
  KEY_PATH="$(mktemp -t AuthKey).p8"
  CLEANUP_KEY=1
  printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" > "$KEY_PATH"
fi

cleanup() {
  if [[ "$CLEANUP_KEY" == "1" ]]; then
    rm -f "$KEY_PATH"
  fi
}
trap cleanup EXIT

if [[ "$ARTIFACT" == *.dmg ]]; then
  echo "==> Pre-flight: codesign check on app inside DMG"
  ATTACH_OUT="$(hdiutil attach -nobrowse -readonly "$ARTIFACT")"
  MOUNT_POINT="$(echo "$ATTACH_OUT" | awk 'END { print $NF }')"
  APP_IN_DMG="$(find "$MOUNT_POINT" -maxdepth 2 -name '*.app' -print -quit)"
  if [[ -z "$APP_IN_DMG" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null || true
    echo "error: no .app found inside DMG" >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_IN_DMG"
  hdiutil detach "$MOUNT_POINT" >/dev/null
elif [[ "$ARTIFACT" == *.app ]]; then
  codesign --verify --deep --strict --verbose=2 "$ARTIFACT"
fi

echo "==> Submitting for notarization: $ARTIFACT"
xcrun notarytool submit "$ARTIFACT" \
  --key "$KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"

echo "==> Gatekeeper assessment"
spctl --assess --type install --verbose=4 "$ARTIFACT" || \
  spctl --assess --type open --context context:primary-signature --verbose=4 "$ARTIFACT"

echo "Notarization complete."
