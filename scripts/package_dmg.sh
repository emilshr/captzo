#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(xcodebuild -scheme Captzo -showBuildSettings 2>/dev/null | awk -F' = ' '/MARKETING_VERSION/ { print $2; exit }')"
fi
VERSION="${VERSION#v}"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/Captzo.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/export}"
DMG_DIR="${DMG_DIR:-$ROOT_DIR/build/dmg}"
STAGING="${DMG_DIR}/staging"
DMG_PATH="${DMG_DIR}/Captzo-${VERSION}.dmg"

mkdir -p "$DMG_DIR" "$EXPORT_PATH" "$(dirname "$ARCHIVE_PATH")"

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "error: APPLE_TEAM_ID is required for release packaging" >&2
  exit 1
fi

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  echo "error: CODE_SIGN_IDENTITY is required (full 'Developer ID Application: …' string)" >&2
  exit 1
fi

echo "==> Archiving Captzo ${VERSION} (${CONFIGURATION})"
xcodebuild archive \
  -scheme Captzo \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  SKIP_INSTALL=NO \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual

echo "==> Exporting Developer ID app"
TMP_EXPORT="$ROOT_DIR/build/ExportOptions.plist"
mkdir -p "$ROOT_DIR/build"
cat > "$TMP_EXPORT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
EOF

if ! xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$TMP_EXPORT"; then
  echo "error: exportArchive failed; refusing to ship archive Products fallback" >&2
  exit 1
fi

find_app() {
  local base="$1"
  if [[ -d "$base/Captzo.app" ]]; then
    echo "$base/Captzo.app"
  elif [[ -d "$base/captzo.app" ]]; then
    echo "$base/captzo.app"
  else
    echo ""
  fi
}

APP_SRC="$(find_app "$EXPORT_PATH")"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "error: exported app bundle not found in $EXPORT_PATH" >&2
  exit 1
fi

echo "==> Staging Captzo.app and verifying signature"
rm -rf "$STAGING"
mkdir -p "$STAGING"
# Homebrew cask expects Captzo.app
cp -R "$APP_SRC" "$STAGING/Captzo.app"
codesign --force --deep --options runtime --timestamp \
  --sign "$CODE_SIGN_IDENTITY" \
  "$STAGING/Captzo.app"
codesign --verify --deep --strict --verbose=2 "$STAGING/Captzo.app"
spctl --assess --type execute --verbose=4 "$STAGING/Captzo.app" || true
ln -sf /Applications "$STAGING/Applications"

echo "==> Creating DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Captzo" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Hash-only sidecar for Homebrew automation, plus human-readable copy.
HASH="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
printf '%s\n' "$HASH" > "${DMG_PATH}.sha256"
echo "${HASH}  $(basename "$DMG_PATH")"
echo "DMG ready: $DMG_PATH"
