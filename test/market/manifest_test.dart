// The manifest.json parser.
//
// Ports the manifest branch of `mkt_fetch_scripts` (`src/market_dialog.c:92-123`).
// The distinction that matters throughout: `null` means "this is not a
// manifest, fall back to the contents API"; `[]` means "this is a manifest and
// it lists nothing".

import 'package:taskpin/core/market/manifest.dart';
import 'package:taskpin/core/market/market_models.dart';
import 'package:test/test.dart';

void main() {
  group('a well-formed manifest', () {
    const String body = '''
{
  "name": "TaskPin Plugins",
  "scripts": [
    {"name": "Docker", "file": "docker_status.lua", "description": "Docker 容器状态", "author": "bestK", "version": "1.2"},
    {"name": "Crypto", "file": "crypto_price.lua", "description": "币价", "author": "bestK", "version": "0.9"}
  ]
}
''';

    test('parses every field', () {
      final List<MarketScript>? scripts = parseManifest(body, sourceRepo: 'bestK/taskpin-plugins');
      expect(scripts, isNotNull);
      expect(scripts, hasLength(2));

      final MarketScript first = scripts!.first;
      expect(first.name, 'Docker');
      expect(first.file, 'docker_status.lua');
      expect(first.description, 'Docker 容器状态');
      expect(first.author, 'bestK');
      expect(first.version, '1.2');
      expect(first.sourceRepo, 'bestK/taskpin-plugins');
      expect(first.isUsable, isTrue);
      expect(first.hasManifestMetadata, isTrue);
    });

    test('stamps the source repo onto every entry', () {
      final List<MarketScript>? scripts = parseManifest(body, sourceRepo: 'a/b');
      expect(scripts!.every((MarketScript s) => s.sourceRepo == 'a/b'), isTrue);
    });

    test('isManifestBody agrees', () {
      expect(isManifestBody(body), isTrue);
    });
  });

  group('not a manifest -> null, so the caller falls back', () {
    test('invalid JSON', () {
      expect(parseManifest('<html>404</html>'), isNull);
      expect(isManifestBody('<html>404</html>'), isFalse);
    });

    test('valid JSON that is not an object', () {
      expect(parseManifest('[1,2,3]'), isNull);
      expect(parseManifest('"a string"'), isNull);
      expect(parseManifest('42'), isNull);
    });

    test('an object with no scripts key', () {
      expect(parseManifest('{"name":"x"}'), isNull);
      expect(isManifestBody('{"name":"x"}'), isFalse);
    });

    test('scripts present but not an array', () {
      // `if (c->key && strcmp(c->key,"scripts")==0 && c->type == JSON_ARRAY)`
      // — a string or object under `scripts` does not count.
      expect(parseManifest('{"scripts":"docker.lua"}'), isNull);
      expect(parseManifest('{"scripts":{"a":1}}'), isNull);
      expect(isManifestBody('{"scripts":{}}'), isFalse);
    });

    test('an empty scripts array IS a manifest with zero entries', () {
      // Distinct from null: this repo HAS a manifest, it just lists nothing.
      expect(parseManifest('{"scripts":[]}'), isEmpty);
      expect(isManifestBody('{"scripts":[]}'), isTrue);
    });
  });

  group('entry tolerance', () {
    test('an entry with no file is dropped', () {
      // `if (ms->file[0]) s_mkt->script_count++;` — market_dialog.c:114.
      const String body = '{"scripts":[{"name":"NoFile"},{"name":"Ok","file":"ok.lua"}]}';
      final List<MarketScript>? scripts = parseManifest(body);
      expect(scripts, hasLength(1));
      expect(scripts!.single.file, 'ok.lua');
    });

    test('an entry with an empty-string file is dropped', () {
      const String body = '{"scripts":[{"name":"x","file":""}]}';
      expect(parseManifest(body), isEmpty);
    });

    test('a non-object entry is skipped', () {
      const String body = '{"scripts":["notanobject",{"file":"ok.lua"}]}';
      final List<MarketScript>? scripts = parseManifest(body);
      expect(scripts, hasLength(1));
    });

    test('non-string fields read as empty, matching the C str_val guard', () {
      // `if (!f->key || !f->str_val) continue;` — a number or object is ignored
      // and the field keeps its default rather than being stringified.
      const String body =
          '{"scripts":[{"file":"a.lua","name":123,"description":{"x":1},"author":null,"version":true}]}';
      final MarketScript s = parseManifest(body)!.single;
      expect(s.name, '');
      expect(s.description, '');
      expect(s.author, '');
      expect(s.version, '');
    });

    test('an entry that omits name keeps it empty (the UI falls back to the file)', () {
      final MarketScript s = parseManifest('{"scripts":[{"file":"a.lua"}]}')!.single;
      expect(s.name, '');
      expect(s.file, 'a.lua');
    });

    test('the list is capped at kMaxMarketScripts', () {
      final StringBuffer buf = StringBuffer('{"scripts":[');
      for (int i = 0; i < kMaxMarketScripts + 10; i++) {
        if (i > 0) buf.write(',');
        buf.write('{"file":"s$i.lua"}');
      }
      buf.write(']}');
      expect(parseManifest(buf.toString()), hasLength(kMaxMarketScripts));
    });

    test('a duplicate file is NOT deduplicated here', () {
      // The C reader does not dedupe either; the UI's installed-state check is
      // what makes a duplicate visible.
      const String body = '{"scripts":[{"file":"a.lua"},{"file":"a.lua"}]}';
      expect(parseManifest(body), hasLength(2));
    });
  });

  group('search predicate', () {
    const MarketScript s = MarketScript(
      name: 'Docker Status',
      file: 'docker.lua',
      description: '容器状态监控',
      author: 'bestK',
    );

    test('matches on name, case-insensitively', () {
      expect(s.matches('docker'), isTrue);
      expect(s.matches('DOCKER'), isTrue);
      expect(s.matches('Status'), isTrue);
    });

    test('matches on description', () {
      expect(s.matches('容器'), isTrue);
    });

    test('does NOT match on author or file', () {
      // Deliberate: matching author would make every entry from the default
      // source match a query containing "bestK".
      expect(s.matches('bestK'), isFalse);
      expect(s.matches('docker.lua'), isFalse);
    });

    test('an empty or whitespace query matches everything', () {
      expect(s.matches(''), isTrue);
      expect(s.matches('   '), isTrue);
    });

    test('a non-match returns false', () {
      expect(s.matches('kubernetes'), isFalse);
    });
  });
}
