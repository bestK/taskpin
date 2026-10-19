// The gh-proxy.com URL rewriter.
//
// This is a pure function library. It performs NO network I/O and it never
// decides "are we in China" itself: that decision is passed in as a parameter.
// That separation is what makes the whole thing unit-testable, and it is the
// only reason `geo.dart` can have a fallback strategy at all.
//
// Behaviour is ported from the C engine's `sys.gh_proxy`
// (`native/engine/tp_sysinfo_win.c:665`), which itself folds together the two
// original call sites:
//
//   lib/update.c:20-26          gh_url()      -> https://gh-proxy.com/https://github.com/<path>
//   src/market_dialog.c:37-42   mkt_build_raw_url()
//                                             -> https://gh-proxy.com/https://raw.githubusercontent.com/...
//
// The rules, in order (identical to the C version):
//
//   1. Not in China            -> return the input unchanged.
//   2. Already proxied         -> return the input unchanged. Re-wrapping would
//                                 produce https://gh-proxy.com/https://gh-proxy.com/...
//   3. Host does not contain
//      "github"                 -> return the input unchanged. gh-proxy.com can
//                                 only fetch from GitHub, so prefixing an
//                                 arbitrary host yields a URL that cannot
//                                 resolve. A substring test covers github.com,
//                                 raw.githubusercontent.com and api.github.com
//                                 without enumerating them.
//   4. Otherwise               -> 'https://gh-proxy.com/' + input.
//
// Rule 3 is the one to be careful about. `lib/update.c`'s `gh_url` prefixes
// unconditionally because its only caller passes a known-GitHub path; the market
// path and `sys.gh_proxy` both operate on arbitrary URLs and must test the host.
// We implement the stricter (host-checked) version everywhere.

/// The mirror prefix. Matches `l_sys_gh_proxy`'s hardcoded literal.
const String kGhProxyPrefix = 'https://gh-proxy.com/';

/// The public GitHub host. `githubPath` builds URLs against this.
const String kGithubHost = 'https://github.com/';

/// The raw-content host, used by the market's manifest fetch.
const String kGithubRawHost = 'https://raw.githubusercontent.com/';

/// The REST API host, used by the market's contents-API fallback.
const String kGithubApiHost = 'https://api.github.com';

/// Rewrites [url] through the gh-proxy.com mirror when [inChina] is true.
///
/// Returns [url] unchanged when:
///  * [inChina] is false, or
///  * [url] is already a gh-proxy.com URL, or
///  * [url]'s host does not contain `github`.
///
/// Never throws: a malformed URL is returned unchanged rather than causing the
/// caller to lose the URL entirely.
String rewriteGithubUrl(String url, {required bool inChina}) {
  if (!inChina) return url;
  if (url.startsWith(kGhProxyPrefix)) return url;
  if (!_hostContainsGithub(url)) return url;
  return '$kGhProxyPrefix$url';
}

/// Builds `https://github.com/<path>` (or the proxied equivalent).
///
/// This is the shape `lib/update.c`'s `gh_url` produces, and its callers pass
/// bare paths such as `bestK/taskpin/raw/master/version.txt`.
String githubPath(String path, {required bool inChina}) {
  final String bare = path.startsWith('/') ? path.substring(1) : path;
  return rewriteGithubUrl('$kGithubHost$bare', inChina: inChina);
}

/// Builds `https://raw.githubusercontent.com/<path>` (or the proxied
/// equivalent). The market uses this for `manifest.json`.
String rawGithubPath(String path, {required bool inChina}) {
  final String bare = path.startsWith('/') ? path.substring(1) : path;
  return rewriteGithubUrl('$kGithubRawHost$bare', inChina: inChina);
}

/// Builds `https://api.github.com/<path>` (or the proxied equivalent).
///
/// Note the deliberate divergence from the old market dialog, which wrapped only
/// its raw URL and left `api.github.com` unproxied (`market_dialog.c:126`).
/// `lib/update.c:28-36` (`gh_api_get`) *does* wrap the API host, and
/// `sys.gh_proxy`'s documented rule is "any host containing github", so
/// proxying it is both consistent and more useful in China.
String apiGithubPath(String path, {required bool inChina}) {
  final String bare = path.startsWith('/') ? path.substring(1) : path;
  return rewriteGithubUrl('$kGithubApiHost/$bare', inChina: inChina);
}

/// True when the URL's host contains `github`.
///
/// Host = everything between `://` and the next `/` (or the end of the string),
/// which is exactly how `l_sys_gh_proxy` slices it. A URL with no `://` is
/// treated as having the whole string for a host, so `github.com/x` (scheme
/// omitted) still matches.
bool _hostContainsGithub(String url) {
  final int schemeEnd = url.indexOf('://');
  final String host;
  if (schemeEnd >= 0) {
    final int hostStart = schemeEnd + 3;
    final int slash = url.indexOf('/', hostStart);
    host = slash >= 0 ? url.substring(hostStart, slash) : url.substring(hostStart);
  } else {
    final int slash = url.indexOf('/');
    host = slash >= 0 ? url.substring(0, slash) : url;
  }
  return host.contains('github');
}
