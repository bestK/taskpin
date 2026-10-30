#!/usr/bin/env bash
# Run the end-to-end suite.
#
# `flutter test integration_test/...` on a desktop device launches the real
# application: real window, real Lua engine, real config directory. It is slow
# (builds the app first) and needs a desktop session, which is why it is NOT
# part of `flutter test` — that one must stay headless and fast.
#
# Usage:
#   tool/e2e.sh              # Windows (default device)
#   tool/e2e.sh -d macos     # any other desktop device
set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-flutter}"

echo "==> analyze"
"$FLUTTER" analyze integration_test

echo "==> e2e"
"$FLUTTER" test integration_test/dialog_e2e_test.dart "$@"
