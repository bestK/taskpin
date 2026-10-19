// The production `HttpFetcher`, as a provider.
//
// One fetcher for the whole app: the market installer, the geo lookup and the
// updater all share it, so a single `http.Client` (and its connection pool) is
// reused rather than each subsystem opening its own.
//
// `HttpPackageFetcher` is created here rather than in the pure-logic layer so
// the market/update code stays testable without `package:http`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../market/http_fetcher.dart';
import '../market/http_package_fetcher.dart';

/// The live network client.
///
/// Overridden in tests with a fake; the default is the real
/// [HttpPackageFetcher]. It is disposed with the container.
final Provider<HttpFetcher> httpFetcherProvider = Provider<HttpFetcher>((Ref ref) {
  final HttpPackageFetcher fetcher = HttpPackageFetcher();
  ref.onDispose(fetcher.close);
  return fetcher;
});
