#!/usr/bin/env sh
# Packages build/statera as an AppImage and a .deb into dist/, bundling libSDL3.
# Usage: scripts/package_linux.sh <version>   (SDL_PREFIX = SDL3 install; needs patchelf, dpkg-deb)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: package_linux.sh <version>}
DEB_VERSION=$(echo "$VERSION" | sed 's/^v//')
SDL_PREFIX=${SDL_PREFIX:-/usr/local}
SDL_SO=$(readlink -f "$SDL_PREFIX/lib/libSDL3.so.0")
cd "$ROOT"
rm -rf dist/linux && mkdir -p dist/linux

# --- AppImage ---
APPDIR=dist/linux/AppDir
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"
cp build/statera "$APPDIR/usr/bin/statera"
cp "$SDL_SO" "$APPDIR/usr/lib/libSDL3.so.0"
patchelf --set-rpath '$ORIGIN/../lib' "$APPDIR/usr/bin/statera"
cp installer/linux/statera.desktop "$APPDIR/statera.desktop"
cp assets/icon/statera.png "$APPDIR/statera.png"
ln -sf usr/bin/statera "$APPDIR/AppRun"
APPIMAGETOOL=${APPIMAGETOOL:-appimagetool}
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$APPDIR" "dist/Statera-$VERSION-linux-x86_64.AppImage"

# --- .deb (installs to /opt/statera, command on PATH, desktop entry and icon) ---
PKG=dist/linux/deb
mkdir -p "$PKG/DEBIAN" "$PKG/opt/statera/bin" "$PKG/opt/statera/lib" "$PKG/usr/bin" \
	"$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/256x256/apps"
cp build/statera "$PKG/opt/statera/bin/statera"
cp "$SDL_SO" "$PKG/opt/statera/lib/libSDL3.so.0"
patchelf --set-rpath '$ORIGIN/../lib' "$PKG/opt/statera/bin/statera"
ln -sf /opt/statera/bin/statera "$PKG/usr/bin/statera"
cp installer/linux/statera.desktop "$PKG/usr/share/applications/statera.desktop"
cp assets/icon/statera.png "$PKG/usr/share/icons/hicolor/256x256/apps/statera.png"
cat > "$PKG/DEBIAN/control" <<EOF
Package: statera
Version: $DEB_VERSION
Section: science
Priority: optional
Architecture: amd64
Depends: libc6, libgl1, libx11-6
Maintainer: Risso Productions
Homepage: https://github.com/NicolasRisso/OpenSPSS
Description: Open-source, SPSS-compatible statistics
 Statera reads and writes .sav files and runs SPSS syntax with output that
 matches SPSS Statistics, in a modern GPU-rendered interface.
EOF
dpkg-deb --build --root-owner-group "$PKG" "dist/statera_${DEB_VERSION}_amd64.deb"
rm -rf dist/linux
ls -l dist
