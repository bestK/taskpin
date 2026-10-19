#!/usr/bin/env bash
# build_dll.sh — build taskpin_engine.dll for the Dart test harness and put it
# where lib/src/library_loader.dart looks first.
#
# The SHIPPED app does NOT use this. It links the engine statically into the
# Flutter runner (docs/FLUTTER_REWRITE_PLAN.md, "C 库的构建方式") so the product
# stays one artifact with no runtime dependency. The DLL exists only because
# `dart test` has no runner to link against.
#
# Toolchain: MSVC, matching the Flutter Windows runner.
#
# Usage:  bash packages/taskpin_engine/tool/build_dll.sh
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"

BUILD_DIR="$REPO/native/engine/build-dll"
DEST_DIR="$PKG/native"

VCVARS="D:\\VS2022BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat"
if [ ! -f "/d/VS2022BuildTools/VC/Auxiliary/Build/vcvars64.bat" ]; then
    echo "build_dll.sh: MSVC not found at $VCVARS" >&2
    echo "  The engine must be built with the same toolchain as the Flutter" >&2
    echo "  Windows runner. Install the VS 'Desktop development with C++' workload." >&2
    exit 1
fi

# Configure + build. The vcvars call is wrapped in a .bat because Git Bash
# mangles nested quotes on the way into cmd.exe.
BAT="$(mktemp -d)/build_dll.bat"
cat > "$BAT" <<BATEOF
@echo off
call "$VCVARS" >nul
cmake -S "$(cygpath -w "$REPO/native/engine")" -B "$(cygpath -w "$BUILD_DIR")" ^
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DTP_BUILD_SHARED=ON || exit /b 1
cmake --build "$(cygpath -w "$BUILD_DIR")" || exit /b 1
BATEOF

cmd //c "$(cygpath -w "$BAT")"

mkdir -p "$DEST_DIR"
cp "$BUILD_DIR/taskpin_engine.dll" "$DEST_DIR/taskpin_engine.dll"
echo "build_dll.sh: $DEST_DIR/taskpin_engine.dll"
