#!/usr/bin/env sh
# Packages build/statera as Statera.app inside a .dmg in dist/, bundling libSDL3.
# Usage: scripts/package_macos.sh <version>   (SDL_PREFIX = SDL3 install built by build_sdl3.sh)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: package_macos.sh <version>}
PLAIN_VERSION=$(echo "$VERSION" | sed 's/^v//')
SDL_PREFIX=${SDL_PREFIX:-/usr/local}
ARCH=$(uname -m)
cd "$ROOT"
rm -rf dist/macos && mkdir -p dist/macos

APP=dist/macos/root/Statera.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp build/statera "$APP/Contents/MacOS/statera"
cp "$SDL_PREFIX/lib/libSDL3.0.dylib" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/statera"
otool -L "$APP/Contents/MacOS/statera"

# Icon: build an .iconset from the 256 px PNG.
ICONSET=dist/macos/statera.iconset
mkdir -p "$ICONSET"
for s in 16 32 64 128 256; do
	sips -z $s $s assets/icon/statera.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
for s in 16 32 64 128; do
	cp "$ICONSET/icon_$((s * 2))x$((s * 2)).png" "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/statera.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>Statera</string>
	<key>CFBundleDisplayName</key><string>Statera</string>
	<key>CFBundleIdentifier</key><string>com.rissoproductions.statera</string>
	<key>CFBundleExecutable</key><string>statera</string>
	<key>CFBundleIconFile</key><string>statera</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$PLAIN_VERSION</string>
	<key>CFBundleVersion</key><string>$PLAIN_VERSION</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>CFBundleDocumentTypes</key><array><dict>
		<key>CFBundleTypeName</key><string>SPSS data file</string>
		<key>CFBundleTypeExtensions</key><array><string>sav</string><string>zsav</string></array>
		<key>CFBundleTypeRole</key><string>Editor</string>
	</dict></array>
</dict></plist>
EOF

# Ad-hoc signature: required to run on Apple Silicon (not notarized; first launch needs right-click → Open).
codesign --force --deep --sign - "$APP"
ln -s /Applications dist/macos/root/Applications
hdiutil create -volname "Statera" -srcfolder dist/macos/root -ov -format UDZO "dist/Statera-$VERSION-macos-$ARCH.dmg"
rm -rf dist/macos
ls -l dist
