#!/bin/zsh
# Builds a universal Pasteroo.app and its release zip into ./build.
# SIGN_ID picks the signing identity: the self-signed "Pasteroo Self-Signed" by default
# (keeps the Accessibility permission across updates), "-" for ad-hoc, or a Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.2.0}"
SIGN_ID="${SIGN_ID:-Pasteroo Self-Signed}"
REPO="alessandroscaudo/Pasteroo"
SPARKLE_PUBLIC_KEY="Gxq0hgrOo+ofaQHNRwNQaTa4z3dhIZQATSdtBybxAgg="
APP=build/Pasteroo.app

swift build -c release --arch arm64 --arch x86_64
PRODUCTS="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/Pasteroo" "$APP/Contents/MacOS/Pasteroo"
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# App icon: the binary renders the 1024 px artwork, sips scales it into an iconset.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$APP/Contents/MacOS/Pasteroo" --icon "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  [[ $size == 512 ]] || sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
  <key>CFBundleExecutable</key><string>Pasteroo</string>
  <key>CFBundleIdentifier</key><string>it.scaudo.pasteroo</string>
  <key>CFBundleName</key><string>Pasteroo</string>
  <key>CFBundleDisplayName</key><string>Pasteroo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Alessandro Scaudo</string>
  <key>SUFeedURL</key><string>https://github.com/${REPO}/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Sign inside out: Sparkle's helpers, the framework, then the app.
# Hardened runtime only with a Developer ID: its library validation would reject a
# framework signed by a self-signed certificate, which has no Team ID.
SIGN=(codesign --force --sign "$SIGN_ID")
[[ "$SIGN_ID" == "Developer ID Application:"* ]] && SIGN+=(--options runtime --timestamp)
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"

ZIP="build/Pasteroo-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $APP and $ZIP"
