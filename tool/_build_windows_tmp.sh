#!/usr/bin/env bash
# Temporary build driver (deleted after use). Kept out of the repo's Dart/CMake.
set -u
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd /d/workspace/taskpin
/d/flutter/bin/flutter.bat build windows --debug 2>&1 | tail -100
echo "EXIT=${PIPESTATUS[0]}"
