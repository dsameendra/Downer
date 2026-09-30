#!/bin/zsh
# Builds dist/Downer-<version>.dmg from the current checkout:
#   universal Release build -> ad-hoc signature -> designed installer window.
# Needs Xcode and python3. dmgbuild is installed into dist/.venv on first run.
set -euo pipefail
cd "$(dirname "$0")/.."

DIST="$PWD/dist"
# build outside the checkout: folders like ~/Documents get Finder metadata that codesign rejects
BUILD="$(mktemp -d)/build"
mkdir -p "$DIST"

echo "==> Building Downer (Release, universal)"
xcodebuild -project Downer.xcodeproj -scheme Downer -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build | tail -n 3

APP="$BUILD/Build/Products/Release/Downer.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST/Downer-$VERSION.dmg"

echo "==> Signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Drawing the installer background"
swift scripts/dmg/make_background.swift "$DIST"

echo "==> Packaging $DMG"
if [[ ! -x "$DIST/.venv/bin/dmgbuild" ]]; then
  python3 -m venv "$DIST/.venv"
  "$DIST/.venv/bin/pip" install --quiet dmgbuild
fi
rm -f "$DMG"
"$DIST/.venv/bin/dmgbuild" -s scripts/dmg/dmg_settings.py \
  -D app="$APP" \
  -D icon="$APP/Contents/Resources/Downer.icns" \
  -D background="$DIST/background.png" \
  "Downer $VERSION" "$DMG"

hdiutil verify "$DMG" | tail -n 1
( cd "$DIST" && shasum -a 256 "Downer-$VERSION.dmg" | tee "Downer-$VERSION.dmg.sha256" )
echo "==> Done: $DMG"
