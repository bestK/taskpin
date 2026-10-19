// Geo-location for the "should we use the gh-proxy.com mirror?" decision.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS FILE EXISTS AT ALL (the finding that shaped it)
// ─────────────────────────────────────────────────────────────────────────────
// The two C implementations both answer "are we in China?" from a single
// endpoint:
//
//   src/market_dialog.c:18-35   mkt_check_geo()   api.ip.sb/geoip -> country_code
//   lib/update.c:11-17          is_in_china()     api.ip.sb/geoip -> strstr
//
// That endpoint is not trustworthy. On the development machine used for this
// rewrite — a machine physically in China — `api.ip.sb/geoip` answers **Japan**.
// The consequence in the shipping product is concrete: a Chinese user's market
// downloads and self-updates go straight at raw.githubusercontent.com instead of
// the mirror, and fail or crawl.
//
// The engine's unified `sys.*` API already separates the two questions
// (`native/engine/tp_sysinfo_win.c:507-530`, documented in `docs/LUA_API.md:366`):
//
//   sys.country()   OS region setting   instant, offline, never lies about the
//                                       setting, says nothing about where the
//                                       machine actually is
//   sys.is_china()  network geo-IP      cached, needs the network, and is wrong
//                                       when the service is wrong
//
// So this file tries the network first — it is the more precise signal when it
// works, and it is what the C code used — and falls back to the OS region when
// the network cannot answer at all. It deliberately does NOT let the OS region
// override a successful network answer, because that would change behaviour for
// every user whose Windows region and physical location differ; the observed
// failure is the network service being wrong, not the network being unreachable,
// and that case is surfaced to the user through [GeoDecision.source] instead.
//
// ─────────────────────────────────────────────────────────────────────────────
// The cache
// ─────────────────────────────────────────────────────────────────────────────
// One resolution per process, like `static int s_is_china = -1`
// (`tp_sysinfo_win.c:613`). The request must happen at most once: scripts and
// the market both consult it, and the updater polls every 30 minutes.
//
// Pure Dart. No Flutter, no `dart:io` — the OS region arrives through an
// injected callback, which is what lets a test drive every branch offline.

import 'dart:convert';

import 'http_fetcher.dart';

/// The endpoint both C implementations use.
const String kGeoEndpoint = 'https://api.ip.sb/geoip';

/// The environment variable that overrides the endpoint.
///
/// Mirrors `tp_geo_url()` (`tp_sysinfo_win.c:614`), which exists purely as a
/// diagnostic/testing seam: pointing it at an unreachable host is how the
/// offline path gets exercised without unplugging the machine.
const String kGeoEndpointEnvVar = 'TASKPIN_GEO_URL';

/// Which signal produced a [GeoDecision].
///
/// Surfaced so the UI can explain a surprising mirror choice, and so tests can
/// assert which path ran rather than only what the answer was.
enum GeoSource {
  /// `api.ip.sb/geoip` answered and parsed. Authoritative.
  network,

  /// The network could not answer (transport failure, non-2xx, unparseable
  /// body); the OS region setting decided instead.
  osRegion,

  /// Neither signal was usable. Pessimistic default: not in China, matching
  /// `s_is_china = 0` at `tp_sysinfo_win.c:626` and `is_in_china()`'s
  /// `return FALSE` on a failed request (`lib/update.c:13`).
  fallback,
}

/// The resolved answer plus which signal produced it.
class GeoDecision {
  const GeoDecision({required this.inChina, required this.source, this.countryCode = ''});

  /// Whether GitHub URLs should be routed through gh-proxy.com.
  final bool inChina;

  /// Which signal decided [inChina].
  final GeoSource source;

  /// The ISO 3166-1 alpha-2 code observed, or `''` when none was.
  final String countryCode;

  /// The pessimistic default: assume no mirror, and say so.
  static const GeoDecision unknown =
      GeoDecision(inChina: false, source: GeoSource.fallback);

  @override
  String toString() => 'GeoDecision(inChina: $inChina, source: ${source.name}, cc: $countryCode)';
}

/// The OS-region seam.
///
/// On the real app this is backed by the engine's `sys.country()`. It is a
/// callback rather than a direct FFI call so that (a) this file stays pure Dart
/// and (b) tests can drive the fallback without an engine.
///
/// May return `''` when the platform cannot answer, which is treated as "no
/// OS-region signal".
typedef OsRegionLookup = Future<String> Function();

/// Resolves the China question once per instance, and caches it.
class GeoLocator {
  GeoLocator({
    required HttpFetcher fetcher,
    OsRegionLookup? osRegion,
    String? endpointOverride,
  })  : _fetcher = fetcher,
        _osRegion = osRegion,
        _endpoint = (endpointOverride != null && endpointOverride.isNotEmpty)
            ? endpointOverride
            : kGeoEndpoint;

  final HttpFetcher _fetcher;

  /// The OS-region lookup. `null` means the platform has no such capability
  /// (or the caller did not wire one), and the fallback stage is skipped.
  final OsRegionLookup? _osRegion;

  final String _endpoint;

  GeoDecision? _cached;

  /// How many times the network was actually consulted. Test-visible so the
  /// "at most once per process" guarantee can be asserted.
  int get networkCallCount => _networkCallCount;
  int _networkCallCount = 0;

  /// The cached decision, or `null` before the first [resolve].
  GeoDecision? get cached => _cached;

  /// Resolves the China question, consulting the network at most once.
  ///
  /// Safe to call from every refresh: after the first call this returns the
  /// cached value synchronously-ish (an already-completed future).
  Future<GeoDecision> resolve() async {
    final GeoDecision? cached = _cached;
    if (cached != null) return cached;

    final GeoDecision decision = await _decide();
    _cached = decision;
    return decision;
  }

  /// Convenience for callers that only need the boolean.
  Future<bool> isInChina() async => (await resolve()).inChina;

  /// Forces a re-resolution on the next [resolve]. Test/diagnostic only.
  void reset() {
    _cached = null;
    _networkCallCount = 0;
  }

  Future<GeoDecision> _decide() async {
    _networkCallCount++;
    final HttpResult result = await _fetcher.getText(_endpoint);

    final String? code = _countryCodeFrom(result);
    if (code != null) {
      return GeoDecision(
        inChina: code == 'CN',
        source: GeoSource.network,
        countryCode: code,
      );
    }

    // The network could not answer. Fall back to how the machine is configured.
    final OsRegionLookup? lookup = _osRegion;
    if (lookup != null) {
      String os = '';
      try {
        os = (await lookup()).trim().toUpperCase();
      } catch (_) {
        // A failing platform lookup is the same as no lookup: fall through to
        // the pessimistic default rather than failing the whole resolution.
        os = '';
      }
      if (os.isNotEmpty) {
        return GeoDecision(
          inChina: os == 'CN',
          source: GeoSource.osRegion,
          countryCode: os,
        );
      }
    }

    return GeoDecision.unknown;
  }

  /// Extracts `country_code` from a geo-IP response.
  ///
  /// Returns `null` when the response cannot be read, so the caller falls back.
  /// The two parsing strategies are the two C ones, tried in that order:
  ///
  ///  1. JSON parse and read `country_code` — `mkt_check_geo`
  ///     (`src/market_dialog.c:23-33`), the more precise of the two.
  ///  2. A raw substring test for `"country_code":"CN"` — `is_in_china`
  ///     (`lib/update.c:14`), for bodies the minimal decoder rejects.
  ///
  /// Note the asymmetry the substring fallback introduces: it can only ever
  /// conclude "CN", never "not CN". That is why it is only reached when the
  /// JSON parse failed outright, and why a body that parses but says `JP` is
  /// trusted as `JP` (the observed bug) rather than being second-guessed.
  String? _countryCodeFrom(HttpResult result) {
    if (result.isTransportFailure) return null;
    if (!result.isSuccess) return null;

    final String body = result.body.trim();
    if (body.isEmpty) return null;

    // Strategy 1: real JSON.
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map) {
        final dynamic cc = decoded['country_code'];
        if (cc is String && cc.isNotEmpty) return cc.toUpperCase();
        // Parsed as JSON but with no country_code: not a geo-IP answer.
        return null;
      }
    } on FormatException {
      // Fall through to strategy 2.
    }

    // Strategy 2: the substring test from lib/update.c:14.
    if (body.contains('"country_code":"CN"')) return 'CN';

    return null;
  }
}
