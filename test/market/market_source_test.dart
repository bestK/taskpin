// Fetching a source's catalog: manifest first, contents-API fallback.
//
// Ports `mkt_fetch_scripts` (`src/market_dialog.c:79-177`). No network: every
// request goes through a scripted fake, and the URL that would have been
// requested is asserted directly.

import 'package:taskpin/core/market/market_models.dart';
import 'package:taskpin/core/market/market_source.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  late FakeFetcher fetcher;

  setUp(() => fetcher = FakeFetcher());

  group('manifest path', () {
    test('uses manifest.json when present and does not call the API', () async {
      fetcher.onText('/manifest.json', '''
{"scripts":[{"name":"Docker","file":"docker.lua","description":"d","author":"a","version":"1"}]}
''');

      final MarketFetch fetch = await fetchMarketCatalog(
        'bestK/taskpin-plugins',
        fetcher: fetcher,
        inChina: false,
      );

      expect(fetch.viaManifest, isTrue);
      expect(fetch.scripts, hasLength(1));
      expect(fetch.scripts.single.name, 'Docker');
      expect(fetch.scripts.single.sourceRepo, 'bestK/taskpin-plugins');
      expect(fetcher.callCount, 1, reason: 'the API is not consulted when a manifest works');
      expect(
        fetcher.requestedUrls.single,
        'https://raw.githubusercontent.com/bestK/taskpin-plugins/master/manifest.json',
      );
    });

    test('requests manifest.json from the master branch', () async {
      // `mkt_build_raw_url` hardcodes `master` (market_dialog.c:39-41).
      fetcher.onText('/manifest.json', '{"scripts":[]}');
      await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetcher.requestedUrls.single, contains('/master/manifest.json'));
    });

    test('an empty manifest list is still viaManifest', () async {
      fetcher.onText('/manifest.json', '{"scripts":[]}');
      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.viaManifest, isTrue);
      expect(fetch.scripts, isEmpty);
      expect(fetch.error, isEmpty, reason: 'an empty repo is not a failure');
      expect(fetcher.callCount, 1);
    });
  });

  group('API fallback', () {
    test('a 404 on manifest.json falls through to the contents API', () async {
      fetcher.onText('/manifest.json', 'Not Found', status: 404);
      fetcher.onText('/contents/', '''
[{"name":"a.lua"},{"name":"README.md"},{"name":"b.lua"}]
''');

      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);

      expect(fetch.viaManifest, isFalse);
      expect(fetch.scripts.map((MarketScript s) => s.file).toList(),
          <String>['a.lua', 'b.lua']);
      expect(fetcher.callCount, 2);
      expect(
        fetcher.requestedUrls.last,
        'https://api.github.com/repos/a/b/contents/',
      );
    });

    test('an HTML 404 page (200 status) still falls through', () async {
      // GitHub sometimes serves an HTML body with a 200 for a missing raw path.
      fetcher.onText('/manifest.json', '<html>404</html>');
      fetcher.onText('/contents/', '[{"name":"a.lua"}]');

      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.viaManifest, isFalse);
      expect(fetch.scripts, hasLength(1));
    });

    test('JSON with no scripts key falls through', () async {
      fetcher.onText('/manifest.json', '{"name":"just a package.json"}');
      fetcher.onText('/contents/', '[{"name":"a.lua"}]');
      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.viaManifest, isFalse);
      expect(fetch.scripts, hasLength(1));
    });

    test('the API request carries the Accept header GitHub needs', () async {
      // `src/market_dialog.c:127-128`.
      fetcher.onText('/manifest.json', 'nope', status: 404);
      fetcher.onText('/contents/', '[]');
      await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);

      final Map<String, String>? headers = fetcher.requestedHeaders.last;
      expect(headers, isNotNull);
      expect(headers!['Accept'], 'application/vnd.github.v3+json');
    });

    test('an API 404 object yields an empty list, not an error', () async {
      fetcher.onText('/manifest.json', 'nope', status: 404);
      fetcher.onText('/contents/', '{"message":"Not Found"}');
      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.scripts, isEmpty);
      expect(fetch.error, isEmpty, reason: 'the repo simply has no .lua files');
    });
  });

  group('proxy rewriting', () {
    test('both URLs are proxied when in China', () async {
      fetcher.onText('/manifest.json', 'nope', status: 404);
      fetcher.onText('/contents/', '[]');

      await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: true);

      expect(fetcher.requestedUrls[0], startsWith('https://gh-proxy.com/'));
      expect(fetcher.requestedUrls[0], contains('raw.githubusercontent.com'));
      expect(fetcher.requestedUrls[1], startsWith('https://gh-proxy.com/'));
      expect(fetcher.requestedUrls[1], contains('api.github.com'),
          reason: 'a documented divergence from market_dialog.c, which left the API unproxied');
    });

    test('nothing is proxied when not in China', () async {
      fetcher.onText('/manifest.json', '{"scripts":[]}');
      await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetcher.requestedUrls.single, isNot(contains('gh-proxy')));
    });
  });

  group('failure handling', () {
    test('a total transport failure reports an error rather than "0 scripts"', () async {
      fetcher.offline = true;
      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.scripts, isEmpty);
      expect(fetch.error, isNotEmpty, reason: 'the UI must not claim the repo is empty');
    });

    test('a manifest transport failure with a working API still succeeds', () async {
      fetcher.onFailure('/manifest.json');
      fetcher.onText('/contents/', '[{"name":"a.lua"}]');
      final MarketFetch fetch =
          await fetchMarketCatalog('a/b', fetcher: fetcher, inChina: false);
      expect(fetch.scripts, hasLength(1));
      expect(fetch.error, isEmpty);
    });
  });

  group('input handling', () {
    test('an empty repo string makes no request at all', () async {
      final MarketFetch fetch =
          await fetchMarketCatalog('   ', fetcher: fetcher, inChina: false);
      expect(fetch.scripts, isEmpty);
      expect(fetcher.callCount, 0);
    });

    test('the repo is trimmed before use', () async {
      fetcher.onText('/manifest.json', '{"scripts":[]}');
      await fetchMarketCatalog('  a/b  ', fetcher: fetcher, inChina: false);
      expect(fetcher.requestedUrls.single, contains('a/b/master/manifest.json'));
      expect(fetcher.requestedUrls.single, isNot(contains('  ')));
    });
  });
}
