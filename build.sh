#!/usr/bin/env bash
# Build Unscrew.app and install it for the current user.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Unscrew.app"
# Releases (CI) are universal; local builds only for this Mac.
ARGS=(-c release)
[ -n "${CI:-}" ] && ARGS+=(--arch arm64 --arch x86_64)
echo "==> swift build ${ARGS[*]}"
swift build "${ARGS[@]}"
BIN_DIR="$(swift build "${ARGS[@]}" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# Helpers ship inside the bundle so they share its signature and permissions.
for bin in Unscrew scroll-invert mic-guard; do
	cp "$BIN_DIR/$bin" "$APP/Contents/MacOS/$bin"
done

mkdir -p "$APP/Contents/Resources/features"
cp features/*.sh "$APP/Contents/Resources/features/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Unscrew</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.robin.unscrew</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Unscrew</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>Feature scripts control system settings.</string>
</dict>
</plist>
PLIST

# Redraw the icon only when tools/make-icon.swift changed.
ICON_PNG="build/AppIcon-1024.png"
if [ ! -e "$ICON_PNG" ] || [ tools/make-icon.swift -nt "$ICON_PNG" ]; then
	echo "==> drawing $ICON_PNG"
	swift tools/make-icon.swift "$ICON_PNG"
fi

ICONSET="build/AppIcon.iconset"
echo "==> building $ICONSET"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$APP/Contents/Resources"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signatures change every build and void granted permissions.
# tools/make-signing-cert.sh creates a stable identity.
IDENTITY="Unscrew Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then SIGN="$IDENTITY"; else SIGN=-; fi
echo "==> codesign ($SIGN)"
codesign --force --deep --sign "$SIGN" "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1

# CI only builds; zip it from build/.
[ -n "${CI:-}" ] && { echo "==> built $APP"; exit 0; }

echo "==> installing to ~/Applications/Unscrew.app"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Unscrew.app"
cp -R "$APP" "$HOME/Applications/Unscrew.app"
echo "==> installed ~/Applications/Unscrew.app"
