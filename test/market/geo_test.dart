// The geo-IP check and its OS-region fallback.
//
// The finding that shaped this file: `api.ip.sb/geoip` answers **Japan** on a
// machine that is physically in China (observed on the development machine for
// this rewrite). A Chinese user whose geo lookup says JP gets no gh-proxy
// mirror, so market downloads and self-updates go straight at
// raw.githubusercontent.com and fail or crawl.
//
// The fallback is the engine's `sys.country()` — the OS region setting, which
// `native/engine/tp_sysinfo_win.c:536` exposes and `docs/LUA_API.md:366`
// documents as the "how is the machine configured" question, distinct from
// "where does the network think we are".

import 'package:taskpin/core/market/geo.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('network path', () {
    test('country_code CN means in China, via the network', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '{"country_code":"CN","ip":"1.2.3.4"}');
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isTrue);
      expect(decision.source, GeoSource.network);
      expect(decision.countryCode, 'CN');
    });

    test('country_code JP means not in China, via the network', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '{"country_code":"JP","ip":"1.2.3.4"}');
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isFalse);
      expect(decision.source, GeoSource.network);
      expect(decision.countryCode, 'JP');
    });

    test('the raw substring fallback from lib/update.c:14 still works', () async {
      // `is_in_china()` does a strstr rather than a JSON parse. Kept as the
      // second strategy for bodies the decoder rejects.
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(
        body: '{"country_code":"CN"',
      );
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isTrue);
      expect(decision.source, GeoSource.network);
    });

    test('the result is cached: the network is hit at most once', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '{"country_code":"CN"}');
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      await locator.resolve();
      await locator.resolve();
      await locator.isInChina();
      await locator.resolve();

      expect(fetcher.calls, 1, reason: 's_is_china = -1, checked once per process');
      expect(locator.networkCallCount, 1);
    });
  });

  group('OS-region fallback', () {
    test('the network is unreachable and the OS region is CN -> in China', () async {
      // This is the case the finding is about: the machine is in China, the
      // geo service is blocked or broken, and only the OS setting knows.
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => 'CN',
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isTrue);
      expect(decision.source, GeoSource.osRegion);
      expect(decision.countryCode, 'CN');
    });

    test('the network is unreachable and the OS region is US -> not in China', () async {
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => 'US',
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isFalse);
      expect(decision.source, GeoSource.osRegion);
    });

    test('a non-2xx response falls back to the OS region', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: 'rate limited', status: 429);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => 'CN',
      );

      expect((await locator.resolve()).source, GeoSource.osRegion);
    });

    test('an unparseable body falls back to the OS region', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '<html>captive portal</html>');
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => 'CN',
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isTrue);
      expect(decision.source, GeoSource.osRegion);
    });

    test('the OS region is lowercased/trimmed before comparison', () async {
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => '  cn \n',
      );
      expect((await locator.resolve()).inChina, isTrue);
    });

    test('an empty OS region is treated as no signal, not as a negative answer', () async {
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => '',
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isFalse);
      expect(decision.source, GeoSource.fallback);
    });

    test('a throwing OS-region lookup degrades instead of propagating', () async {
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => throw StateError('no engine'),
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.source, GeoSource.fallback);
      expect(decision.inChina, isFalse);
    });

    test('the network answer WINS over a conflicting OS region', () async {
      // The observed bug is the network service being WRONG, not unreachable.
      // Letting the OS region override a successful network answer would change
      // behaviour for every user whose Windows region and physical location
      // differ, so the network answer is authoritative when it parses. The
      // mismatch is surfaced through `source` for the UI to explain instead.
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '{"country_code":"JP"}');
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        osRegion: () async => 'CN',
      );

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isFalse);
      expect(decision.source, GeoSource.network,
          reason: 'JP came from the network; the OS region is not consulted');
    });
  });

  group('fallback default', () {
    test('no network and no OS-region lookup -> pessimistic "not in China"', () async {
      // Matches `s_is_china = 0` (tp_sysinfo_win.c:626) and
      // `is_in_china()`'s `return FALSE` (lib/update.c:13).
      final ScriptedGeoFetcher fetcher = ScriptedGeoFetcher(body: '', fail: true);
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      final GeoDecision decision = await locator.resolve();
      expect(decision.inChina, isFalse);
      expect(decision.source, GeoSource.fallback);
      expect(GeoDecision.unknown.inChina, isFalse);
    });
  });

  group('endpoint override', () {
    test('the endpoint can be redirected, mirroring TASKPIN_GEO_URL', () async {
      // `tp_geo_url()` (tp_sysinfo_win.c:614) exists purely so the offline path
      // can be exercised without unplugging the machine.
      final FakeFetcher fetcher = FakeFetcher();
      fetcher.onText('/geoip', '{"country_code":"CN"}');
      final GeoLocator locator = GeoLocator(
        fetcher: fetcher,
        endpointOverride: 'http://127.0.0.1:9/geoip',
      );

      expect((await locator.resolve()).inChina, isTrue);
      expect(fetcher.requestedUrls.single, 'http://127.0.0.1:9/geoip');
    });

    test('an empty override falls back to the default endpoint', () {
      final GeoLocator locator = GeoLocator(
        fetcher: FakeFetcher(),
        endpointOverride: '',
      );
      expect(locator.cached, isNull);
      // The default is asserted indirectly through the constant.
      expect(kGeoEndpoint, 'https://api.ip.sb/geoip');
      expect(kGeoEndpointEnvVar, 'TASKPIN_GEO_URL');
    });
  });

  group('reset', () {
    test('reset clears the cache so the next resolve hits the network again', () async {
      final ScriptedGeoFetcher fetcher =
          ScriptedGeoFetcher(body: '{"country_code":"CN"}');
      final GeoLocator locator = GeoLocator(fetcher: fetcher);

      await locator.resolve();
      locator.reset();
      await locator.resolve();

      expect(fetcher.calls, 2);
      expect(locator.networkCallCount, 1, reason: 'counter restarts with the cache');
    });
  });
}
