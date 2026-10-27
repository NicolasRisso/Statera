#!/usr/bin/env sh
# Fetches and builds the Odin Dear ImGui bindings (docking branch) into vendor/imgui (Linux/macOS).
# Requires: git, python3, clang, ar.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/vendor/imgui"
COMMIT=a116eb1ceaa6acde60219efdd56bf6c2e1aedf4c # gitlab.com/L-4/odin-imgui, imgui v1.92.8-docking

[ -d "$DEST" ] || git clone --quiet https://gitlab.com/L-4/odin-imgui.git "$DEST"
git -C "$DEST" fetch --quiet origin
git -C "$DEST" checkout --quiet "$COMMIT"

# Only build the backends we use.
python3 - "$DEST/build.py" <<'EOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
src = re.sub(r"wanted_backends = \[.*?\]", 'wanted_backends = ["sdl3", "opengl3"]', src, count=1, flags=re.S)
open(path, "w").write(src)
EOF

cd "$DEST" && python3 build.py
echo "imgui ready at $DEST"
