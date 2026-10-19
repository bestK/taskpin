// The version-comparison contract.
//
// ─────────────────────────────────────────────────────────────────────────────
// READ THIS BEFORE CHANGING ANYTHING HERE
// ─────────────────────────────────────────────────────────────────────────────
// `lib/update.c:146` compares versions with `strcmp`. That is NOT semver and it
// produces an ordering that is wrong by any versioning standard: `1.10.0` sorts
// BEFORE `1.6.8`. The consequence is that a machine running 1.6.8 is never
// offered 1.10.0.
//
// Every existing installation depends on that behaviour, and the rewrite plan
// pins it explicitly ("**字符串比较**（非 semver，必须保持，否则老用户升级行为
// 变化）"). So these tests assert the WRONG-BY-DESIGN ordering on purpose. The
// first test's NAME says so, so that a future reader who "fixes" it is told
// exactly what they are breaking.

import 'package:taskpin/core/update/version_compare.dart';
import 'package:test/test.dart';

void main() {
  group('strcmp semantics', () {
    test(
      'strcmp semantics (NOT semver): 1.10.0 sorts BEFORE 1.6.8, so an install '
      'running 1.6.8 is NOT offered 1.10.0 — this is the shipping behaviour',
      () {
        // This is the whole point of the file. `strcmp("1.10.0", "1.6.8") < 0`
        // because the second character '1' (0x31) < '6' (0x36). A semver
        // implementation would return > 0 here, and swapping to one would
        // silently change the upgrade path for every installed copy.
        expect(compareVersions('1.10.0', '1.6.8'), lessThan(0));
        expect(isUpdateAvailable('1.10.0', '1.6.8'), isFalse);

        // The mirror case, which is what users actually experience: 1.6.9 IS
        // offered to a 1.6.8 install, because '9' > '8'.
        expect(compareVersions('1.6.9', '1.6.8'), greaterThan(0));
        expect(isUpdateAvailable('1.6.9', '1.6.8'), isTrue);
      },
    );

    test('a strictly greater string is an update', () {
      expect(isUpdateAvailable('1.6.9', '1.6.8'), isTrue);
      expect(isUpdateAvailable('1.7.0', '1.6.8'), isTrue);
      expect(isUpdateAvailable('2.0.0', '1.6.8'), isTrue);
      expect(isUpdateAvailable('1.6.80', '1.6.8'), isTrue);
    });

    test('an equal version is NOT an update (no update loop)', () {
      // Strict `> 0`. If this became `>= 0` the updater would re-download
      // itself on every check, forever.
      expect(compareVersions('1.6.8', '1.6.8'), 0);
      expect(isUpdateAvailable('1.6.8', '1.6.8'), isFalse);
    });

    test('a lower string is not an update', () {
      expect(isUpdateAvailable('1.6.7', '1.6.8'), isFalse);
      expect(isUpdateAvailable('0.9.0', '1.6.8'), isFalse);
      // Another wrong-by-semver case: 1.5.10 < 1.6.8 as strings ('5' < '6').
      expect(isUpdateAvailable('1.5.10', '1.6.8'), isFalse);
    });
  });

  group('trimVersionTag', () {
    test('strips leading/trailing spaces, CR and LF', () {
      // `lib/update.c:141-144` strips exactly these three characters.
      expect(trimVersionTag('  1.6.9  '), '1.6.9');
      expect(trimVersionTag('\r\n1.6.9\r\n'), '1.6.9');
      expect(trimVersionTag('\n\n  1.6.9 \r\n'), '1.6.9');
    });

    test('a version.txt with a trailing newline still compares equal', () {
      // This is the real shape of the file: `version.txt` is `1.6.8\n`.
      expect(compareVersions('1.6.8\n', '1.6.8'), 0);
      expect(isUpdateAvailable('1.6.8\n', '1.6.8'), isFalse);
    });

    test('does NOT strip tabs, matching the C loop', () {
      // The C loop only checks ' ', '\r', '\n'. A tab is left in place, which
      // makes the comparison fail loudly rather than silently — kept as-is.
      expect(trimVersionTag('\t1.6.9'), '\t1.6.9');
    });

    test('does NOT strip a leading v', () {
      // A `v1.7.0` version.txt compares as "v1.7.0" > "1.6.8" because 'v'
      // (0x76) > '1' (0x31), so it always reports an update. That is the
      // shipping behaviour; reproduced rather than guessed at.
      expect(trimVersionTag('v1.7.0'), 'v1.7.0');
      expect(isUpdateAvailable('v1.7.0', '1.6.8'), isTrue);
    });

    test('an all-whitespace body trims to empty', () {
      expect(trimVersionTag('  \r\n  '), '');
    });
  });

  group('compareVersions', () {
    test('returns a negative int, zero, or a positive int — never throws', () {
      expect(compareVersions('', '1.6.8'), lessThan(0));
      expect(compareVersions('1.6.8', ''), greaterThan(0));
      expect(compareVersions('', ''), 0);
    });

    test('only the remote side is trimmed', () {
      // The current version is a compile-time constant; trimming it would mask
      // a malformed build rather than surfacing it.
      expect(compareVersions(' 1.6.8 ', '1.6.8'), 0);
      expect(compareVersions('1.6.8', ' 1.6.8 '), greaterThan(0));
    });
  });
}
