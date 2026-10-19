#!/usr/bin/env python3
"""Run TaskPin's pure-Dart tests without Flutter.

Why this exists
---------------
The repo's `pubspec.yaml` depends on Flutter (`flutter`, `flutter_localizations`,
`flutter_riverpod`, ...). Resolving it needs `flutter pub get`, which needs a
working Flutter SDK. In this working copy `bin/cache/flutter_tools.snapshot` is
missing, so `flutter test` cannot run.

Everything under `lib/core/{market,update,elevate}/` is deliberately pure Dart
(no Flutter imports). This script makes those files testable anyway:

  1. It uses a standalone shim package (`E:\\tmp\\tp_dart_harness`) whose
     package name is `taskpin` and whose only dependencies are `test`, `http`
     and `path` — all resolvable without Flutter.
  2. It copies this repo's `lib/core/**` into that package's `lib/core/**`, so
     `package:taskpin/core/...` imports resolve to exactly the files under test.
  3. It copies the pure-Dart test directories in and runs `dart test`.

Why a copy rather than a path dependency
----------------------------------------
A path dependency would pull the Flutter-flavoured `pubspec.yaml` and fail to
resolve. A directory junction (`mklink /J`) was tried and rejected by this
environment. Copying is cheap (21 small files) and means the repo is never
modified: no `.dart_tool`, no `pubspec.lock`, no stray artifacts.

Run this again after changing any core file.

Usage:
    python tool/run_pure_dart_tests.py [dart-test-args...]
"""

import json
import os
import shutil
import subprocess
import sys

REPO = r"D:\workspace\taskpin"
HARNESS = r"E:\tmp\tp_dart_harness"
DART = r"D:\flutter\bin\cache\dart-sdk\bin\dart.exe"

# Copied into the harness so package:taskpin/... resolves to the real sources.
CORE_SOURCE = os.path.join(REPO, "lib", "core")

# Only these test directories are pure Dart. Everything else in test/ needs
# Flutter (it imports flutter_test).
TEST_DIRS = ["market", "update", "elevate", "support"]


def main() -> int:
    if not os.path.exists(DART):
        print(f"FATAL: no Dart SDK at {DART}")
        return 2
    if not os.path.exists(os.path.join(HARNESS, ".dart_tool", "package_config.json")):
        print(f"FATAL: harness not resolved. Run `dart pub get` in {HARNESS}")
        return 2

    # 1. Sync the core sources under test.
    dest_core = os.path.join(HARNESS, "lib", "core")
    if os.path.exists(dest_core):
        shutil.rmtree(dest_core)
    shutil.copytree(CORE_SOURCE, dest_core)
    n_core = sum(len(fs) for _r, _d, fs in os.walk(dest_core))

    # 2. Sync the pure-Dart tests.
    dest_test = os.path.join(HARNESS, "test")
    if os.path.exists(dest_test):
        shutil.rmtree(dest_test)
    os.makedirs(dest_test)
    n_tests = 0
    for name in TEST_DIRS:
        src = os.path.join(REPO, "test", name)
        if not os.path.isdir(src):
            continue
        for root, _dirs, files in os.walk(src):
            rel = os.path.relpath(root, os.path.join(REPO, "test"))
            out_dir = os.path.join(dest_test, rel)
            os.makedirs(out_dir, exist_ok=True)
            for fn in files:
                shutil.copy2(os.path.join(root, fn), os.path.join(out_dir, fn))
                n_tests += 1
    print(f"synced {n_core} core files and {n_tests} test files into {HARNESS}")

    # 3. Run.
    env = dict(os.environ)
    env["PUB_HOSTED_URL"] = "https://pub.flutter-io.cn"
    env["FLUTTER_STORAGE_BASE_URL"] = "https://storage.flutter-io.cn"
    argv = [DART, "test", "--reporter", "expanded"]
    argv.extend(sys.argv[1:])
    print("running:", " ".join(argv))
    return subprocess.call(argv, cwd=HARNESS, env=env)


if __name__ == "__main__":
    raise SystemExit(main())

