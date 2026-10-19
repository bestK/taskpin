// Source-list management: the 8-source cap, duplicates, validation.
//
// Ports `src/market_dialog.c:246-286`.

import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/market/market_sources.dart';
import 'package:test/test.dart';

void main() {
  group('addSource', () {
    test('appends a valid source', () {
      final List<String> sources = <String>[];
      expect(addSource(sources, 'bestK/taskpin-plugins'), SourceAddResult.added);
      expect(sources, <String>['bestK/taskpin-plugins']);
    });

    test('trims surrounding whitespace before storing', () {
      final List<String> sources = <String>[];
      expect(addSource(sources, '  bestK/plugins  '), SourceAddResult.added);
      expect(sources.single, 'bestK/plugins');
    });

    test('an empty input is rejected with `empty`', () {
      final List<String> sources = <String>[];
      expect(addSource(sources, ''), SourceAddResult.empty);
      expect(addSource(sources, '   '), SourceAddResult.empty);
      expect(sources, isEmpty);
    });

    test('a duplicate is rejected CASE-INSENSITIVELY, matching lstrcmpiW', () {
      final List<String> sources = <String>['bestK/taskpin-plugins'];
      expect(addSource(sources, 'bestK/taskpin-plugins'), SourceAddResult.duplicate);
      expect(addSource(sources, 'BESTK/TaskPin-Plugins'), SourceAddResult.duplicate);
      expect(sources, hasLength(1));
    });

    test('a malformed source is rejected with `invalidFormat`', () {
      final List<String> sources = <String>[];
      expect(addSource(sources, 'no-slash-here'), SourceAddResult.invalidFormat);
      expect(addSource(sources, 'a/b/c'), SourceAddResult.invalidFormat);
      expect(addSource(sources, '/repo'), SourceAddResult.invalidFormat);
      expect(addSource(sources, 'user/'), SourceAddResult.invalidFormat);
      expect(addSource(sources, 'user/re po'), SourceAddResult.invalidFormat);
      expect(sources, isEmpty);
    });

    group('the 8-source cap (CFG_MAX_SOURCES)', () {
      test('the 8th source is accepted and the 9th is refused', () {
        final List<String> sources = <String>[];
        for (int i = 0; i < ConfigLimits.maxSources; i++) {
          expect(addSource(sources, 'user$i/repo'), SourceAddResult.added,
              reason: 'source ${i + 1} of ${ConfigLimits.maxSources} must be accepted');
        }
        expect(sources, hasLength(ConfigLimits.maxSources));
        expect(ConfigLimits.maxSources, 8, reason: 'the message says "最多支持 8 个源"');

        expect(addSource(sources, 'user9/repo'), SourceAddResult.limitReached);
        expect(sources, hasLength(8));
      });

      test('the cap is checked BEFORE the format', () {
        // A user at the limit with a typo is told about the limit, which is the
        // actionable problem. Matches the C order.
        final List<String> sources = List<String>.generate(8, (int i) => 'u$i/r');
        expect(addSource(sources, 'not-a-repo'), SourceAddResult.limitReached);
      });

      test('the cap is checked BEFORE the duplicate check', () {
        final List<String> sources = List<String>.generate(8, (int i) => 'u$i/r');
        expect(addSource(sources, 'u0/r'), SourceAddResult.limitReached);
      });
    });

    test('canAddSource and remainingSourceSlots track the cap', () {
      final List<String> sources = <String>[];
      expect(canAddSource(sources), isTrue);
      expect(remainingSourceSlots(sources), 8);

      for (int i = 0; i < 8; i++) {
        addSource(sources, 'u$i/r');
      }
      expect(canAddSource(sources), isFalse);
      expect(remainingSourceSlots(sources), 0);
      expect(remainingSourceSlots(sources), isNonNegative);
    });
  });

  group('removeSourceAt', () {
    test('removes and shifts the rest down', () {
      // The C handler shifts with a loop (lines 277-278).
      final List<String> sources = <String>['a/1', 'b/2', 'c/3'];
      expect(removeSourceAt(sources, 0), isTrue);
      expect(sources, <String>['b/2', 'c/3']);
    });

    test('an out-of-range index is a no-op', () {
      final List<String> sources = <String>['a/1'];
      expect(removeSourceAt(sources, -1), isFalse);
      expect(removeSourceAt(sources, 1), isFalse);
      expect(removeSourceAt(sources, 99), isFalse);
      expect(sources, <String>['a/1']);
    });

    test('removing from an empty list is a no-op', () {
      final List<String> sources = <String>[];
      expect(removeSourceAt(sources, 0), isFalse);
    });

    test('removing then re-adding is allowed', () {
      final List<String> sources = <String>['a/1'];
      removeSourceAt(sources, 0);
      expect(addSource(sources, 'a/1'), SourceAddResult.added);
    });
  });

  group('isValidSourceFormat', () {
    test('accepts GitHub-legal user/repo strings', () {
      expect(isValidSourceFormat('bestK/taskpin-plugins'), isTrue);
      expect(isValidSourceFormat('a/b'), isTrue);
      expect(isValidSourceFormat('user.name/repo_name'), isTrue);
      expect(isValidSourceFormat('user-name/repo.js'), isTrue);
      expect(isValidSourceFormat('123/456'), isTrue);
    });

    test('rejects anything else', () {
      expect(isValidSourceFormat(''), isFalse);
      expect(isValidSourceFormat('justuser'), isFalse);
      expect(isValidSourceFormat('a/b/c'), isFalse);
      expect(isValidSourceFormat('a /b'), isFalse);
      expect(isValidSourceFormat('a/b?x=1'), isFalse);
      expect(isValidSourceFormat('https://github.com/a/b'), isFalse);
    });
  });
}
