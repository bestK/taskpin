import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    // ignore: avoid_print
    print('CWD=${Directory.current.path}');
    // ignore: avoid_print
    print('SCRIPT=${Platform.script.toFilePath()}');
    // ignore: avoid_print
    print('RESOLVED=${Platform.script.resolve('.').toFilePath()}');
    final Directory d = Directory.current;
    // ignore: avoid_print
    print('HAS_PUBSPEC=${File('${d.path}/pubspec.yaml').existsSync()}');
    bool found = false;
    Directory cur = d;
    for (int i = 0; i < 8; i++) {
      final File p = File('${cur.path}/pubspec.yaml');
      if (p.existsSync() && p.readAsStringSync().contains('taskpin_design')) {
        // ignore: avoid_print
        print('PKG_ROOT=${cur.path}');
        found = true;
        break;
      }
      final Directory parent = cur.parent;
      if (parent.path == cur.path) break;
      cur = parent;
    }
    // ignore: avoid_print
    print('FOUND=$found');
  });
}
