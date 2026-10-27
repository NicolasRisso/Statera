#!/usr/bin/env sh
# Builds the Statera desktop app into build/ (Linux/macOS).
# Usage: scripts/build.sh [version]   (SDL_PREFIX points at an SDL3 install; default /usr/local)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-dev}
SDL_PREFIX=${SDL_PREFIX:-/usr/local}
cd "$ROOT"
mkdir -p build
odin build src/app -o:speed -vet -strict-style -out:build/statera \
	-define:STATERA_VERSION="$VERSION" -extra-linker-flags:"-L$SDL_PREFIX/lib"
echo "built build/statera"
