// The HTTP seam.
//
// Everything in `lib/core/market/` and `lib/core/update/` talks to the network
// through [HttpFetcher], never through `package:http` directly. Two reasons:
//
//   1. Tests can drive the whole market and the whole updater against an
//      in-process `HttpServer` on loopback, with no network at all. The Phase 10
//      and Phase 11 acceptance criteria both require exactly that ("URL 构造器
//      单测，不打网络"; "本地 HTTP 服务器提供 bump 过的 version.txt + 假 exe").
//   2. It keeps the decision "which URL do we hit" separable from "did the
//      request succeed", which is what makes the geo fallback testable.
//
// [HttpFetcher] is the interface; [HttpPackageFetcher] is the real one, in a
// separate file (`http_fetcher.dart`) so that pure-logic tests can import the
// interface without pulling `package:http` in.

/// One HTTP response, reduced to what the market and updater actually need.
class HttpResult {
  const HttpResult({
    required this.statusCode,
    required this.body,
    this.bodyBytes,
  });

  /// HTTP status. `0` means the request never completed (DNS failure, TLS
  /// failure, timeout, connection refused).
  final int statusCode;

  /// The body decoded as UTF-8. Empty for a binary fetch that used
  /// [bodyBytes].
  final String body;

  /// The raw bytes, when the caller asked for them. `null` for a text fetch.
  final List<int>? bodyBytes;

  /// True when the request completed with a 2xx status.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// True when the request never reached the server.
  bool get isTransportFailure => statusCode == 0;

  /// The number of bytes available, whichever representation is populated.
  int get length => bodyBytes?.length ?? body.length;

  @override
  String toString() => 'HttpResult($statusCode, ${length}B)';
}

/// The network seam.
///
/// Implementations must never throw for a network-level failure: return
/// [HttpResult] with `statusCode: 0` instead. The market's fallback chain and
/// the updater's "check failed" path both depend on failure being a value, not
/// an exception — that is how `http_request_sync` returning `NULL` behaves in
/// the C code (`lib/httputil.c:29`).
abstract class HttpFetcher {
  /// GETs [url] and decodes the body as UTF-8.
  ///
  /// [headers] are added verbatim. [maxBytes] caps the download; the C default
  /// is 256 KiB (`DEFAULT_MAX_SIZE`, `lib/httputil.c:7`) and the updater raises
  /// it to 8 MiB for the exe (`lib/update.c:40`).
  Future<HttpResult> getText(
    String url, {
    Map<String, String>? headers,
    int? maxBytes,
  });

  /// GETs [url] and returns the raw bytes.
  ///
  /// Separate from [getText] because a binary download must not be UTF-8
  /// decoded — doing so corrupts every byte above 0x7F, which is most of an
  /// executable.
  Future<HttpResult> getBytes(
    String url, {
    Map<String, String>? headers,
    int? maxBytes,
  });
}

/// A fetcher that always fails. Useful as a default so a service constructed
/// without a fetcher degrades instead of crashing.
class OfflineFetcher implements HttpFetcher {
  const OfflineFetcher();

  @override
  Future<HttpResult> getText(String url, {Map<String, String>? headers, int? maxBytes}) async =>
      const HttpResult(statusCode: 0, body: '');

  @override
  Future<HttpResult> getBytes(String url, {Map<String, String>? headers, int? maxBytes}) async =>
      const HttpResult(statusCode: 0, body: '', bodyBytes: <int>[]);
}
