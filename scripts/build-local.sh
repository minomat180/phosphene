#!/bin/sh
# Build the fork, sign it for this Mac only, and optionally install it.
#
#   scripts/build-local.sh            build and sign into build/Phosphene.app
#   scripts/build-local.sh --install  also replace /Applications/Phosphene.app
#
# SIGN_IDENTITY picks the signing identity; the default "-" signs ad hoc.
set -eu

cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:--}"
DERIVED="build/DerivedData"
APP="build/Phosphene.app"

xcodebuild -project Phosphene.xcodeproj -scheme Phosphene -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build -quiet

rm -rf "$APP"
cp -R "$DERIVED/Build/Products/Release/Phosphene.app" "$APP"
# Xcode registered the copy it built; WallpaperAgent must only ever launch the installed one.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$DERIVED/Build/Products/Release/Phosphene.app" 2>/dev/null || true

EXT_ENTITLEMENTS="build/PhospheneExtension.entitlements"
cat > "$EXT_ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --options runtime --timestamp=none -s "$IDENTITY" \
  --entitlements "$EXT_ENTITLEMENTS" "$APP/Contents/Extensions/PhospheneExtension.appex"
codesign --force --options runtime --timestamp=none -s "$IDENTITY" \
  --entitlements Phosphene/Phosphene.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  osascript -e 'quit app "Phosphene"' 2>/dev/null || true
  [ -e /Applications/Phosphene.app ] && trash /Applications/Phosphene.app
  ditto "$APP" /Applications/Phosphene.app
  "$LSREGISTER" -f /Applications/Phosphene.app
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  killall WallpaperAgent 2>/dev/null || true
  open /Applications/Phosphene.app
  echo "Installed /Applications/Phosphene.app"
fi
