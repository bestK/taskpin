// The design system's own rule, enforced mechanically.
//
// The plan's Phase 4 acceptance criterion:
//
//   "token 测试断言 token 文件之外没有裸 `Color(0x...)`（用 lint/测试强制）"
//
// This test walks the package's own `lib/` tree, finds every `Color(0x...)`
// literal, and asserts that each one lives under `lib/src/tokens/`.
//
// It is a source-text test rather than a reflection test on purpose: the rule
// is about where the LITERAL appears, and a value that has been passed around
// through a variable is invisible to any runtime check.
//
// NOTE ON PATHS: the package root is resolved by walking UP from
// `Directory.current` looking for the `pubspec.yaml` that declares
// `name: taskpin_design`. It is deliberately NOT `Directory('lib')`.
//
// Running `flutter test` from inside the package sets cwd to the package, but
// running `flutter test packages/taskpin_design` from the repo root does NOT —
// cwd stays at the repo root, and `Directory('lib')` then resolves to the
// APPLICATION's `lib/`. That silently made this test scan the wrong tree: it
// reported the app's colour picker as a violation of a rule that only governs
// this package. Resolving the root explicitly means the test always measures
// what its name claims.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories where raw colour literals are permitted.
///
/// `tokens/` is the whole point of the three-layer system: primitives and the
/// frozen bar palette are the two places where a literal is the honest
/// representation. Everything else must go through the semantic layer.
const List<String> allowedPrefixes = <String>[
  'lib/src/tokens/',
];

/// The package name this test governs, matched against the root pubspec.
const String packageName = 'taskpin_design';

/// Walks up from [from] looking for the directory whose `pubspec.yaml` declares
/// [packageName]. Returns null when no such directory exists.
///
/// Both the level itself and its `packages/<name>/` subdirectory are checked at
/// every step, because cwd depends on how the suite was invoked:
///
///   * `cd packages/taskpin_design && flutter test` — cwd IS the package.
///   * `flutter test packages/taskpin_design` from the repo root — cwd is the
///     repo root, and the package is a DESCENDANT, not an ancestor. A walk-up
///     alone finds nothing here, which is what made this test fail with
///     "could not locate the package root".
Directory? _findPackageRoot(Directory from) {
  Directory dir = from.absolute;
  while (true) {
    for (final Directory candidate in <Directory>[
      dir,
      Directory('${dir.path}${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}$packageName'),
    ]) {
      final File pubspec =
          File('${candidate.path}${Platform.pathSeparator}pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      final String text = pubspec.readAsStringSync();
      if (RegExp('^name:\\s*$packageName\\s*\$', multiLine: true)
          .hasMatch(text)) {
        return candidate;
      }
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Matches `Color(0x...)` in any form, including expressions such as
/// `Color(0xFF000000 | value)` — the point is that a hard-coded hex is
/// invisible to a theme swap, however it is spelled.
///
/// Deliberately does NOT match `Color.fromARGB(...)` or `Colors.red`: those
/// are not the failure mode this rule is about (a named Material colour at
/// least announces itself, and `fromARGB` takes channel values).
final RegExp _rawColorLiteral = RegExp(r'Color\(\s*0x');

/// Strip line comments so a literal mentioned in documentation does not trip
/// the check.
String _stripComments(String source) {
  final StringBuffer out = StringBuffer();
  for (final String line in source.split('\n')) {
    final int idx = line.indexOf('//');
    out.writeln(idx >= 0 ? line.substring(0, idx) : line);
  }
  return out.toString();
}

void main() {
  group('no raw colour literals outside the token layer', () {
    test('lib/ contains no Color(0x...) outside lib/src/tokens/', () {
      final Directory? root = _findPackageRoot(Directory.current);
      expect(
        root,
        isNotNull,
        reason: 'Could not locate the $packageName package root by walking up '
            'from ${Directory.current.path}.',
      );

      final Directory libDir =
          Directory('${root!.path}${Platform.pathSeparator}lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'Expected a lib/ directory under ${root.path}.',
      );

      final List<String> violations = <String>[];

      for (final FileSystemEntity entity
          in libDir.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        if (!entity.path.endsWith('.dart')) {
          continue;
        }

        final String path = entity.path.replaceAll(r'\', '/');

        // Normalise to a package-relative path for the allow-list check.
        final String relative =
            path.startsWith('lib/') ? path : path.substring(path.indexOf('lib/'));

        final bool allowed =
            allowedPrefixes.any((String p) => relative.startsWith(p));
        if (allowed) {
          continue;
        }

        final String source = _stripComments(entity.readAsStringSync());
        for (final RegExpMatch match in _rawColorLiteral.allMatches(source)) {
          final int lineNumber =
              source.substring(0, match.start).split('\n').length;
          violations.add('$relative:$lineNumber  ${match.group(0)}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Raw Color(0x...) literals must live in lib/src/tokens/ only. '
            'Read the colour from TaskPinTheme.of(context) instead.\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('the detector actually detects (guards against a vacuous pass)', () {
      // A test that always passes because its regex is broken is worse than no
      // test. Prove the pattern matches a known literal.
      expect(
        _rawColorLiteral.hasMatch('const c = Color(0xFF123456);'),
        isTrue,
      );
      expect(
        _rawColorLiteral.hasMatch('final c = Color(0x8F06080B);'),
        isTrue,
      );
      // ...and does not match things that are fine.
      expect(
        _rawColorLiteral.hasMatch('final c = Color.fromARGB(255, 1, 2, 3);'),
        isFalse,
      );
      expect(
        _rawColorLiteral.hasMatch('final c = Colors.red;'),
        isFalse,
      );
    });

    test('the allow-list is not over-broad', () {
      // If someone widens the allow-list to `lib/` this test fails, which is
      // the point: the rule is only meaningful while the list is narrow.
      expect(allowedPrefixes.length, 1);
      expect(allowedPrefixes.first, 'lib/src/tokens/');
    });
  });
}
