// The GitHub contents-API fallback listing.
//
// Ports `src/market_dialog.c:126-152`.

import 'package:taskpin/core/market/github_api.dart';
import 'package:taskpin/core/market/market_models.dart';
import 'package:test/test.dart';

void main() {
  group('parseContentsListing', () {
    test('keeps .lua files and ignores everything else', () {
      const String body = '''
[
  {"name": "docker_status.lua", "type": "file"},
  {"name": "README.md", "type": "file"},
  {"name": "manifest.json", "type": "file"},
  {"name": "src", "type": "dir"},
  {"name": "crypto_price.lua", "type": "file"}
]
''';
      final List<MarketScript> scripts =
          parseContentsListing(body, sourceRepo: 'bestK/taskpin-plugins');
      expect(scripts.map((MarketScript s) => s.file).toList(),
          <String>['docker_status.lua', 'crypto_price.lua']);
    });

    test('a directory entry is skipped naturally (its name has no .lua suffix)', () {
      // The C code does not check `type`; a dir named `foo.lua` WOULD be listed.
      const String body = '[{"name":"weird.lua","type":"dir"}]';
      expect(parseContentsListing(body), hasLength(1));
    });

    test('name and file are both the filename, and author is the repo', () {
      // `strncpy(ms->name, name); strncpy(ms->file, name);
      //  strcpy(ms->author, repo8);` — lines 144-146.
      const String body = '[{"name":"a.lua"}]';
      final MarketScript s = parseContentsListing(body, sourceRepo: 'bestK/plugins').single;
      expect(s.name, 'a.lua');
      expect(s.file, 'a.lua');
      expect(s.author, 'bestK/plugins');
      expect(s.sourceRepo, 'bestK/plugins');
      expect(s.description, '', reason: 'the API listing carries no description');
      expect(s.version, '');
      expect(s.hasManifestMetadata, isFalse);
    });

    test('a 404 object body yields an empty list, not an error', () {
      // `root->type == JSON_ARRAY` guards this (line 131).
      expect(parseContentsListing('{"message":"Not Found","status":"404"}'), isEmpty);
    });

    test('a non-JSON body yields an empty list', () {
      expect(parseContentsListing('<html>rate limited</html>'), isEmpty);
      expect(parseContentsListing(''), isEmpty);
    });

    test('a JSON array of non-objects yields an empty list', () {
      expect(parseContentsListing('[1,2,"three"]'), isEmpty);
    });

    test('an entry with no name is skipped', () {
      expect(parseContentsListing('[{"type":"file"}]'), isEmpty);
    });

    test('the list is capped at kMaxMarketScripts', () {
      final StringBuffer buf = StringBuffer('[');
      for (int i = 0; i < kMaxMarketScripts + 5; i++) {
        if (i > 0) buf.write(',');
        buf.write('{"name":"s$i.lua"}');
      }
      buf.write(']');
      expect(parseContentsListing(buf.toString()), hasLength(kMaxMarketScripts));
    });
  });

  group('isLuaFileName', () {
    test('accepts a normal .lua filename', () {
      expect(isLuaFileName('docker_status.lua'), isTrue);
      expect(isLuaFileName('a.lua'), isTrue, reason: 'exactly 5 chars is the boundary');
    });

    test('rejects a bare ".lua" with no stem', () {
      // `len < 5` — market_dialog.c:140.
      expect(isLuaFileName('.lua'), isFalse);
      expect(isLuaFileName(''), isFalse);
      expect(isLuaFileName('abc'), isFalse);
    });

    test('rejects other extensions', () {
      expect(isLuaFileName('readme.md'), isFalse);
      expect(isLuaFileName('manifest.json'), isFalse);
      expect(isLuaFileName('luafile'), isFalse);
    });

    test('accepts uppercase, a documented divergence from the C strcmp', () {
      // The C `strcmp(name + len - 4, ".lua")` is byte-exact, so a repo with
      // `Foo.LUA` is invisible to the old market. Matching case-insensitively is
      // deliberate and harmless.
      expect(isLuaFileName('Foo.LUA'), isTrue);
      expect(isLuaFileName('x.Lua'), isTrue);
    });
  });
}
