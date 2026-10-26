#!/usr/bin/env sh
# Push gate: run before every push. Exits non-zero on failure. See AGENTS.md §1.
cd "$(dirname "$0")/.." || exit 1
failed=0
mkdir -p build

# 1-2. Check and test every Odin package under src/.
for pkg in $(find src -name '*.odin' -exec dirname {} \; | sort -u); do
    entry="-no-entry-point"
    grep -qE '^main[[:space:]]*::' "$pkg"/*.odin && entry=""
    if ! odin check "$pkg" $entry -vet -strict-style; then
        echo "FAIL check $pkg"; failed=1; continue
    fi
    if ls "$pkg"/*_test.odin >/dev/null 2>&1; then
        name=$(echo "$pkg" | tr '/.' '__')
        odin test "$pkg" -vet -strict-style "-out:build/test_$name" || { echo "FAIL test $pkg"; failed=1; }
    fi
done

# 4. Clean-room lint: tracked or staged files must not contain IBM material.
bad=$(git ls-files --cached | grep -E '\.(dll|jar|exe|so|dylib|xsd)$|(^|/)syntax_xml/')
bad="$bad $(git grep -l -I -e 'Licensed Materials - Property of IBM' -e '(C) Copyright IBM Corp' -- . ':!scripts/gate.*')"
for f in $bad; do echo "FAIL clean-room: $f"; failed=1; done

[ "$failed" -eq 0 ] || { echo 'GATE FAILED'; exit 1; }
echo 'GATE PASSED'
