// Fetching a market source's catalog: manifest.json, then the contents API.
//
// Ports `mkt_fetch_scripts` (`src/market_dialog.c:79-177`) minus the ListView
// filling:
//
//   1. GET `<raw>/<repo>/master/manifest.json` through the gh-proxy rewriter.
//      The branch is `master`, matching `mkt_build_raw_url` (line 39-41).
//   2. If that yields no `scripts` array — 404, not JSON, no such key — GET
//      `https://api.github.com/repos/<repo>/contents/` with the headers GitHub
//      requires and list the `.lua` entries.
//
// Two deliberate divergences from the C code, both documented at the call site:
//
//   * The API URL is proxied too. The C market proxied only the raw URL
//     (`market_dialog.c:126`), while `lib/update.c:28-36` proxies the API host
//     as well and `sys.gh_proxy`'s documented rule is "any host containing
//     github". Proxying both is consistent and strictly more useful in China.
//   * A transport failure of the manifest fetch and a 404 both fall through to
//     the API. The C code does the same (`if (resp)` guards both the request and
//     the parse), so this is behaviour-compatible.
//
// Pure Dart.

import 'github_api.dart';
import 'gh_proxy.dart';
import 'http_fetcher.dart';
import 'manifest.dart';
import 'market_models.dart';

/// The result of fetching one source.
class MarketFetch {
  const MarketFetch({
    required this.scripts,
    required this.viaManifest,
    this.error = '',
  });

  /// The scripts found. Empty when the repo has none, or when the fetch failed.
  final List<MarketScript> scripts;

  /// True when the list came from `manifest.json`; false when it came from the
  /// contents-API fallback. Drives the "this repo has no manifest" hint.
  final bool viaManifest;

  /// A non-empty human-readable reason when nothing could be fetched at all.
  /// Empty when the fetch succeeded, even if the repo has zero scripts.
  final String error;

  bool get isEmpty => scripts.isEmpty;

  static const MarketFetch failed = MarketFetch(
    scripts: <MarketScript>[],
    viaManifest: false,
  );
}

/// Fetches and parses a source's script catalog.
///
/// [repo] is the `user/repo` string stored in `TaskPinConfig.sources`.
/// [inChina] comes from [GeoLocator] and is passed in rather than computed, so
/// this whole function is testable against a loopback server.
Future<MarketFetch> fetchMarketCatalog(
  String repo, {
  required HttpFetcher fetcher,
  required bool inChina,
}) async {
  final String trimmed = repo.trim();
  if (trimmed.isEmpty) {
    return const MarketFetch(scripts: <MarketScript>[], viaManifest: false);
  }

  // ── 1. manifest.json ──────────────────────────────────────────────────────
  final String manifestUrl = rawGithubPath('$trimmed/master/$kManifestFileName', inChina: inChina);
  final HttpResult manifestResult = await fetcher.getText(manifestUrl);

  if (manifestResult.isSuccess) {
    final List<MarketScript>? scripts =
        parseManifest(manifestResult.body, sourceRepo: trimmed);
    if (scripts != null) {
      return MarketFetch(scripts: scripts, viaManifest: true);
    }
    // Parsed as HTTP but not as a manifest (e.g. GitHub's HTML 404 page):
    // fall through to the API, same as the C code.
  }

  // ── 2. contents API ───────────────────────────────────────────────────────
  final String apiUrl = apiGithubPath('repos/$trimmed/contents/', inChina: inChina);
  final HttpResult apiResult = await fetcher.getText(
    apiUrl,
    headers: const <String, String>{
      // `src/market_dialog.c:127-128`. The API rejects a request with no
      // User-Agent; the fetcher supplies one, but the Accept header is ours.
      'Accept': 'application/vnd.github.v3+json',
    },
  );

  if (apiResult.isTransportFailure) {
    // Nothing answered. Report it rather than showing a misleading "0 scripts".
    return MarketFetch(
      scripts: const <MarketScript>[],
      viaManifest: false,
      error: apiResult.isTransportFailure && manifestResult.isTransportFailure
          ? 'network'
          : 'api',
    );
  }

  // A 404 from the API is an object, not an array, so this yields [] — which is
  // correct: the repo genuinely has no .lua files at its root.
  return MarketFetch(
    scripts: parseContentsListing(apiResult.body, sourceRepo: trimmed),
    viaManifest: false,
  );
}
