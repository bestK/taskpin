// Shared test doubles.
//
// These live in `test/support/` rather than beside one test file because the
// market, geo and update suites all need the same fake network. Pure Dart: no
// Flutter, so `tool/run_pure_dart_tests.py` can copy this directory across.

import 'package:taskpin/core/market/http_fetcher.dart';

/// A scripted [HttpFetcher].
///
/// Routes are matched by SUBSTRING of the URL, longest pattern first, so a test
/// can register `/version.txt` and `/taskpin-x64.exe` without caring about the
/// host or the proxy prefix. Recording `requestedUrls` is what lets a test
/// assert "no request left loopback" and "the loop stopped after a decline".
class FakeFetcher implements HttpFetcher {
  FakeFetcher();

  /// pattern -> response. Patterns are matched with `contains`.
  final Map<String, HttpResult> routes = <String, HttpResult>{};

  /// Every URL requested, in order.
  final List<String> requestedUrls = <String>[];

  /// Every header map passed, in order. Aligned with [requestedUrls].
  final List<Map<String, String>?> requestedHeaders = <Map<String, String>?>[];

  /// When true, every request fails as a transport failure.
  bool offline = false;

  /// Returned for a URL that matches no route. Defaults to a transport failure
  /// so an unregistered URL fails loudly rather than silently 200-ing.
  HttpResult unmatched = const HttpResult(statusCode: 0, body: '');

  /// Registers a UTF-8 text response.
  void onText(String pattern, String body, {int status = 200}) {
    routes[pattern] = HttpResult(statusCode: status, body: body);
  }

  /// Registers a binary response.
  void onBytes(String pattern, List<int> bytes, {int status = 200}) {
    routes[pattern] = HttpResult(statusCode: status, body: '', bodyBytes: bytes);
  }

  /// Registers a transport failure.
  void onFailure(String pattern) {
    routes[pattern] = const HttpResult(statusCode: 0, body: '');
  }

  int get callCount => requestedUrls.length;

  /// The number of requests whose URL contains [pattern].
  int countMatching(String pattern) =>
      requestedUrls.where((String u) => u.contains(pattern)).length;

  HttpResult _resolve(String url) {
    if (offline) return const HttpResult(statusCode: 0, body: '');
    final List<String> patterns = routes.keys.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    for (final String pattern in patterns) {
      if (url.contains(pattern)) return routes[pattern]!;
    }
    return unmatched;
  }

  @override
  Future<HttpResult> getText(String url, {Map<String, String>? headers, int? maxBytes}) async {
    requestedUrls.add(url);
    requestedHeaders.add(headers);
    return _resolve(url);
  }

  @override
  Future<HttpResult> getBytes(String url, {Map<String, String>? headers, int? maxBytes}) async {
    requestedUrls.add(url);
    requestedHeaders.add(headers);
    return _resolve(url);
  }
}

/// A fetcher that counts calls and always reports a fixed country.
class ScriptedGeoFetcher implements HttpFetcher {
  ScriptedGeoFetcher({required this.body, this.status = 200, this.fail = false});

  final String body;
  final int status;
  final bool fail;
  int calls = 0;

  @override
  Future<HttpResult> getText(String url, {Map<String, String>? headers, int? maxBytes}) async {
    calls++;
    if (fail) return const HttpResult(statusCode: 0, body: '');
    return HttpResult(statusCode: status, body: body);
  }

  @override
  Future<HttpResult> getBytes(String url, {Map<String, String>? headers, int? maxBytes}) async {
    calls++;
    if (fail) return const HttpResult(statusCode: 0, body: '', bodyBytes: <int>[]);
    return HttpResult(statusCode: status, body: '', bodyBytes: body.codeUnits);
  }
}
