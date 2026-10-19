// Cross-language parity for the FROZEN bar tokens.
//
// `bar_tokens.dart` says the token list is duplicated in three places (Dart,
// C++, Swift) and that the Flutter preview exists so the manager shows what the
// taskbar will actually draw. That promise is only real if the three copies
// agree — and nothing enforced it. This did diverge: `bar/bg` was
// `0x00000000` in Dart but `0xFF0E1116` in C++, so the preview strip drew a
// transparent background while the real taskbar strip drew near-black. Same for
// `bar/bgHover` and `bar/icon`. The existing test in `bar_tokens_test.dart`
// checks internal consistency only, which is why it stayed green.
//
// The check is textual on purpose. The C++ side is not reachable from Dart (no
// build, no FFI in a unit test), so the honest way to detect drift is to parse
// both sources and compare the literals. A value that has been passed through a
// variable is invisible to any runtime check — exactly the same reasoning as
// `no_raw_colors_test.dart`.

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/src/tokens/bar_tokens.dart';
/// `packageName -> package root`, resolved by walking up from the test's cwd.
///
/// cwd depends on how the suite was invoked, so this checks both the level
/// itself and its `packages/<name>/` child at every step. See
/// `no_raw_colors_test.dart` for the full note on why a walk-up alone is wrong
/// when `flutter test packages/<name>` is run from the repo root.
Directory? _findPackageRoot(Directory from) {
  Directory dir = from.absolute;
  while (true) {
    for (final Directory candidate in <Directory>[
      dir,
      Directory('${dir.path}${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}taskpin_design'),
    ]) {
      final File pubspec =
          File('${candidate.path}${Platform.pathSeparator}pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      final String text = pubspec.readAsStringSync();
      if (RegExp(r'^name:\s*taskpin_design\s*$', multiLine: true).hasMatch(text)) {
        return candidate;
      }
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// `bar/<name>` -> the C constant in `native/win/bar_tokens.h`.
Map<String, String> _parseCppTokens(String source) {
  // Lines look like:
  //   constexpr uint32_t kColorBg        = 0xFF0E1116u;  // bar/bg
  // The trailing comment carries the frozen name, so the map is built from
  // that rather than from the constant's spelling.
  final Map<String, String> out = <String, String>{};
  final RegExp pattern = RegExp(
    r'constexpr\s+uint32_t\s+(\w+)\s*=\s*(0x[0-9A-Fa-f]+)u;\s*//\s*(bar/\S+)',
  );
  for (final RegExpMatch m in pattern.allMatches(source)) {
    out[m.group(3)!] = m.group(2)!.toUpperCase();
  }
  return out;
}

void main() {
  group('frozen bar tokens match the native renderers', () {
    test('Dart and C++ declare the same value for every token', () {
      final Directory? root = _findPackageRoot(Directory.current);
      expect(root, isNotNull, reason: 'could not locate the package root');

      final File cpp = File(
        '${root!.path}${Platform.pathSeparator}native${Platform.pathSeparator}'
        'win${Platform.pathSeparator}bar_tokens.h',
      );
      if (!cpp.existsSync()) {
        // Run as part of the app rather than the package in isolation: the
        // native tree lives in the app, so a package-only checkout has nothing
        // to compare against and the check would be vacuous.
        return;
      }

      final Map<String, String> cppTokens =
          _parseCppTokens(cpp.readAsStringSync());

      expect(
        cppTokens,
        isNotEmpty,
        reason: 'parsed no tokens from bar_tokens.h — did its format change?',
      );

      final List<String> mismatches = <String>[];
      for (final String name in kFrozenBarTokenNames) {
        final Color dart = TpBarColors.all[name]!;
        // ARGB, upper-case, with the 0x prefix and no `u` suffix — the shape
        // the C++ literal is normalised to above.
        final String dartHex =
            '0x${dart.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}';

        final String? cppHex = cppTokens[name];
        if (cppHex == null) {
          mismatches.add('$name: declared in Dart but missing from C++');
        } else if (cppHex != dartHex) {
          mismatches.add('$name: Dart $dartHex vs C++ $cppHex');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'the frozen bar token list must match across Dart and C++:\n'
            '  ${mismatches.join('\n  ')}\n\n'
            'These files are hand-kept in sync on purpose — bar_tokens.dart '
            'explains why the list is frozen. Fix both sides and the preview '
            'strip will then show what the taskbar actually draws.',
      );
    });

    test('the parser found every frozen token in the C++ header', () {
      // Guards the regex itself. If native/win/bar_tokens.h gains a token the
      // parser cannot see, the test above would silently stop checking it.
      final Directory? root = _findPackageRoot(Directory.current);
      expect(root, isNotNull, reason: 'could not locate the package root');

      final File cpp = File(
        '${root!.path}${Platform.pathSeparator}native${Platform.pathSeparator}'
        'win${Platform.pathSeparator}bar_tokens.h',
      );
      if (!cpp.existsSync()) {
        return;
      }

      final Map<String, String> parsed =
          _parseCppTokens(cpp.readAsStringSync());
      for (final String name in kFrozenBarTokenNames) {
        expect(
          parsed.containsKey(name),
          isTrue,
          reason: 'frozen token "$name" is not present as a `bar/` comment in '
              'native/win/bar_tokens.h. Either the C++ side dropped it or its '
              'format changed; either way the parity check above is now blind '
              'to this token.',
        );
      }
    });
  });
}
