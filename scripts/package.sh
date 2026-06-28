#!/usr/bin/env bash
#
# Glyph release packaging: build → sign (Developer ID, hardened runtime) → DMG →
# notarize → staple. Produces dist/Glyph.dmg ready for direct download.
#
# Prerequisites (one-time, see docs/RELEASE.md):
#   - Paid Apple Developer Program membership
#   - A "Developer ID Application" certificate in your login keychain
#   - Notary credentials stored:  xcrun notarytool store-credentials glyph-notary ...
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/package.sh
#   (NOTARY_PROFILE defaults to "glyph-notary"; override via env if needed)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Glyph"
CONFIG="Release"
PROJECT="Glyph.xcodeproj"
APP_NAME="Glyph"
DEV_ID="${DEV_ID:?Set DEV_ID to your 'Developer ID Application: …' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-glyph-notary}"

echo "▶ Ensuring project + web bundles are present…"
[ -d "$PROJECT" ] || xcodegen generate
[ -f "Glyph/Resources/editor/index.html" ] || (cd web && npm install && npm run build)
[ -f "QuickLook/Resources/preview/index.html" ] || (cd web-preview && npm install && npm run build)

echo "▶ Building $CONFIG (unsigned; we sign with Developer ID below)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build >/dev/null

SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null)"
BUILT_DIR="$(printf '%s\n' "$SETTINGS" | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)"
PRODUCT="$(printf '%s\n' "$SETTINGS" | sed -n 's/^ *FULL_PRODUCT_NAME = //p' | head -1)"
APP="$BUILT_DIR/$PRODUCT"
echo "  app: $APP"

echo "▶ Signing inside-out with hardened runtime + secure timestamp…"
QL_ENTITLEMENTS="$ROOT/QuickLook/Glyph-QuickLook.entitlements"
while IFS= read -r -d '' ext; do
  echo "  sign $(basename "$ext")  (sandboxed)"
  # Quick Look extensions MUST be sandboxed or the host won't activate them.
  codesign --force --options runtime --timestamp \
    --entitlements "$QL_ENTITLEMENTS" --sign "$DEV_ID" "$ext"
done < <(find "$APP/Contents/PlugIns" -maxdepth 1 -name '*.appex' -print0 2>/dev/null)
# The host app stays non-sandboxed (direct download → full filesystem access).
codesign --force --options runtime --timestamp --sign "$DEV_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "▶ Gatekeeper assessment (pre-notarization, may say rejected until stapled):"
spctl -a -vv "$APP" 2>&1 || true

echo "▶ Building DMG…"
mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/$APP_NAME.dmg"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "  dmg: $DMG"

echo "▶ Notarizing (this uploads to Apple and waits)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ Release ready: $DMG"
