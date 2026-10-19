#!/usr/bin/env bash
# abi_probe.sh — compile tool/abi_probe.c against native/engine/taskpin_engine.h
# and write the authoritative struct sizes/offsets to
# test/fixtures/abi_layout.json.
#
# The point is PROVENANCE: the numbers hard-coded in test/abi_layout_test.dart
# come from the C compiler that builds the shipped engine, not from anyone's
# arithmetic. Re-run this whenever the header changes, then update the test.
#
# Toolchain: MSVC, the same one the shipped Flutter Windows runner uses. Falls
# back to MinGW gcc only if MSVC is unavailable, and says so, because a layout
# measured with a different compiler is weaker evidence (plain C structs have
# the same ABI here, but "same toolchain" is the honest claim).
#
# Usage:  bash packages/taskpin_engine/tool/abi_probe.sh
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"

OUT="$PKG/test/fixtures/abi_layout.json"
BUILD="$PKG/native/abi-probe"
mkdir -p "$BUILD" "$(dirname "$OUT")"

# cl.exe is a native program: it only understands Windows paths. cygpath ships
# with Git Bash; fall back to a manual /x/ -> X:\ rewrite if it is absent.
winpath() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1" | sed -e 's|^/\([a-zA-Z]\)/|\1:\\|' -e 's|/|\\|g'
    fi
}

SRC_W="$(winpath "$HERE/abi_probe.c")"
INC_W="$(winpath "$REPO/native/engine")"
BUILD_W="$(winpath "$BUILD")"
EXE_W="$(winpath "$BUILD/abi_probe.exe")"

if [ -f "/d/VS2022BuildTools/VC/Auxiliary/Build/vcvars64.bat" ]; then
    echo "[abi_probe] toolchain: MSVC (cl)"
    # Written to a .bat rather than passed as one long cmd /c string: Git Bash
    # mangles nested quotes on the way into cmd.exe, and cl.exe then sees the
    # quote characters as part of the filename. A batch file sidesteps the
    # whole class of problem.
    BAT="$BUILD/abi_probe.bat"
    cat > "$BAT" <<BATEOF
@echo off
call "D:\\VS2022BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat" >nul
cl /nologo /std:c11 /W3 /utf-8 /I "$INC_W" /Fo"$BUILD_W\\\\" /Fe"$EXE_W" "$SRC_W"
BATEOF
    cmd //c "$(winpath "$BAT")"
    PROBE="$BUILD/abi_probe.exe"
else
    echo "[abi_probe] toolchain: MinGW gcc (MSVC not found) — layout evidence is weaker"
    gcc -std=c99 -Wall -Wextra -I "$REPO/native/engine" \
        -o "$BUILD/abi_probe.exe" "$HERE/abi_probe.c"
    PROBE="$BUILD/abi_probe.exe"
fi

"$PROBE" > "$OUT"
echo "[abi_probe] wrote $OUT"
cat "$OUT"
