// Version comparison for the auto-updater.
//
// ─────────────────────────────────────────────────────────────────────────────
// THIS IS NOT SEMVER. THAT IS THE POINT. DO NOT "FIX" IT.
// ─────────────────────────────────────────────────────────────────────────────
// `lib/update.c:146` decides whether an update is available like this:
//
//     if (strcmp(tag, TASKPIN_VERSION) > 0) { ...offer the update... }
//
// where `tag` is the trimmed body of
// `raw.githubusercontent.com/bestK/taskpin/master/version.txt` and
// `TASKPIN_VERSION` is baked in at build time from `version.txt` via the
// Makefile's `-DTASKPIN_VERSION="$(VERSION)"`.
//
// That is a plain lexicographic string comparison. It is wrong as a version
// ordering — it puts `1.10.0` BEFORE `1.6.8`, so a machine running 1.6.8 is
// never offered 1.10.0 — and every existing installation depends on that
// behaviour. Changing it to a real semver compare would silently change the
// upgrade path for the entire installed base, which is exactly the kind of
// change the rewrite plan forbids ("**字符串比较**（非 semver，必须保持，否则老用户
// 升级行为变化）").
//
// Dart's `String.compareTo` compares UTF-16 code units. For the ASCII
// digit-and-dot alphabet that `version.txt` actually contains, that is identical
// to C `strcmp`'s unsigned-byte ordering, so the port is faithful. The one place
// they could diverge is a non-ASCII character in the version string, which would
// require someone to hand-edit `version.txt` into something that is not a
// version — and at that point the C and Dart answers differing is the least of
// the problems.
//
// The test that pins all of this, and whose NAME says why, is
// `test/update/version_compare_test.dart`:
//
//   'strcmp semantics (NOT semver): 1.10.0 sorts BEFORE 1.6.8, so an install
//    running 1.6.8 is NOT offered 1.10.0 — this is the shipping behaviour'
//
// Pure Dart. No Flutter, no `dart:io`.

/// Trims the whitespace `lib/update.c:141-144` trims.
///
/// The C loop strips leading spaces, CR and LF, then trailing spaces, CR and LF.
/// Notably it does NOT strip tabs, and it does not strip a leading `v`. A
/// `version.txt` containing `v1.7.0` would compare as `'v1.7.0'` against
/// `'1.6.8'`, and since `'v'` (0x76) > `'1'` (0x31) that always reports an
/// update — which is the current behaviour, so we reproduce it rather than
/// guess.
String trimVersionTag(String raw) {
  int start = 0;
  int end = raw.length;
  while (start < end && _isStripped(raw.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isStripped(raw.codeUnitAt(end - 1))) {
    end--;
  }
  return raw.substring(start, end);
}

/// C `strcmp(remote, current)` on the trimmed inputs.
///
/// Negative when [remote] sorts before [current], zero when equal, positive
/// when [remote] sorts after. Callers care about the sign.
///
/// [remote] is trimmed because it comes off the network; [current] is NOT
/// trimmed, because it is a compile-time constant and trimming it would mask a
/// malformed build.
int compareVersions(String remote, String current) =>
    trimVersionTag(remote).compareTo(current);

/// Whether [remote] is "greater than" [current] under the shipping rule.
///
/// This is `strcmp(tag, TASKPIN_VERSION) > 0`. Strictly greater: an EQUAL
/// version is not an update, which is what stops the updater re-downloading
/// itself forever.
bool isUpdateAvailable(String remote, String current) =>
    compareVersions(remote, current) > 0;

bool _isStripped(int c) => c == 0x20 || c == 0x0D || c == 0x0A;
