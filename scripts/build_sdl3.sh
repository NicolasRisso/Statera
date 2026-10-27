#!/usr/bin/env sh
# Builds SDL3 (the version our Odin bindings target) as a shared library into $1 (Linux/macOS).
set -e
PREFIX=${1:?usage: build_sdl3.sh <install-prefix>}
SDL_TAG=release-3.4.2
WORK=$(mktemp -d)
git clone --quiet --depth 1 --branch "$SDL_TAG" https://github.com/libsdl-org/SDL.git "$WORK/SDL"

EXTRA=""
# On macOS the dylib's install name is @rpath-relative, so the app bundle can carry it.
[ "$(uname)" = "Darwin" ] && EXTRA="-DCMAKE_INSTALL_NAME_DIR=@rpath -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"

cmake -S "$WORK/SDL" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF \
	-DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX" $EXTRA
cmake --build "$WORK/build" --parallel
cmake --install "$WORK/build"
echo "SDL3 installed to $PREFIX"
