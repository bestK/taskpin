// The real `HttpFetcher`, backed by `package:http`.
//
// Kept in its own file so the pure-logic tests (`test/market/gh_proxy_test.dart`
// and friends) can import `http_fetcher.dart` for the interface without pulling
// `package:http` into their dependency graph.
//
// Two behaviours are worth stating:
//
//   * A network-level failure is converted to `HttpResult(statusCode: 0)`, never
//     thrown. Callers branch on `isTransportFailure`.
//   * `maxBytes` is enforced by truncating after the fact rather than by
//     streaming with a cap. `package:http`'s `get` reads the whole body first.
//     For the sizes involved (a manifest is a few KiB, the exe is ~2 MB against
//     an 8 MiB cap) that is fine, and it matches the C layer, which also reads
//     the full response before checking the size (`lib/httputil.c`).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_fetcher.dart';

/// The C layer's default response cap: `DEFAULT_MAX_SIZE` (`lib/httputil.c:7`).
const int kDefaultMaxBytes = 256 * 1024;

/// The cap the updater raises to for the exe download (`lib/update.c:40`).
const int kUpdateMaxBytes = 8 * 1024 * 1024;

/// The User-Agent every request carries. `lib/httputil.c:14` opens the WinHTTP
/// session as `TaskPin/1.0`, and the market's API call additionally sets
/// `User-Agent: TaskPin` (`src/market_dialog.c:128`) because GitHub rejects an
/// API request without one.
const String kUserAgent = 'TaskPin/1.0';

class HttpPackageFetcher implements HttpFetcher {
  HttpPackageFetcher({http.Client? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Matches `WinHttpSetTimeouts(session, 8000, 8000, 8000, 8000)`
  /// (`lib/httputil.c:26`).
  final Duration timeout;

  Map<String, String> _headers(Map<String, String>? extra) => <String, String>{
        'User-Agent': kUserAgent,
        ...?extra,
      };

  @override
  Future<HttpResult> getText(
    String url, {
    Map<String, String>? headers,
    int? maxBytes,
  }) async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(url), headers: _headers(headers))
          .timeout(timeout);
      final List<int> bytes = response.bodyBytes;
      final int cap = maxBytes ?? kDefaultMaxBytes;
      final List<int> capped = bytes.length > cap ? bytes.sublist(0, cap) : bytes;
      return HttpResult(
        statusCode: response.statusCode,
        body: utf8.decode(capped, allowMalformed: true),
      );
    } catch (_) {
      // Timeout, SocketException, HandshakeException, bad URL: all are
      // "the request did not complete", which is statusCode 0.
      return const HttpResult(statusCode: 0, body: '');
    }
  }

  @override
  Future<HttpResult> getBytes(
    String url, {
    Map<String, String>? headers,
    int? maxBytes,
  }) async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(url), headers: _headers(headers))
          .timeout(timeout);
      final List<int> bytes = response.bodyBytes;
      final int cap = maxBytes ?? kUpdateMaxBytes;
      final List<int> capped = bytes.length > cap ? bytes.sublist(0, cap) : bytes;
      return HttpResult(
        statusCode: response.statusCode,
        body: '',
        bodyBytes: capped,
      );
    } catch (_) {
      return const HttpResult(statusCode: 0, body: '', bodyBytes: <int>[]);
    }
  }

  /// Releases the underlying client when this fetcher created it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
