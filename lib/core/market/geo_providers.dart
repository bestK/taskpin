// The production `GeoLocator`, wired to the engine's `sys.country()`.
//
// `geo.dart` is pure logic that takes the OS-region lookup as a callback
// precisely so it can be tested offline. This file supplies the real callback:
// the engine's `sys.country()` (`native/engine/tp_sysinfo_win.c:536`), read
// through `EngineApi.executeTemplate`.
//
// ─────────────────────────────────────────────────────────────────────────────
// Why the fallback matters here
// ─────────────────────────────────────────────────────────────────────────────
// `api.ip.sb/geoip` answered **Japan** on the China-based machine this rewrite
// was developed on. With no fallback, a Chinese user's market downloads and
// self-updates go straight at raw.githubusercontent.com and fail. When the
// network cannot answer at all, the OS region setting — which the engine reads
// instantly and offline — decides instead. See `geo.dart` for the full rationale
// and for why the network answer still wins when it parses.
//
// `executeTemplate('return sys.country()')` is used rather than a bespoke FFI
// call because the engine already registers `sys.country()` as a Lua function
// and the template path is the same one the expression editor uses. A script
// returning a bare string lands in `ScriptResult.display`.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_provider.dart';
import '../net/http_providers.dart';
import 'geo.dart';

/// Reads the OS region through the engine, or `''` when it cannot.
///
/// Never throws: a failure here is the same as "no OS-region signal", and
/// `GeoLocator` already treats an empty/`''` answer that way.
Future<String> _osRegionFromEngine(Ref ref) async {
  try {
    final engine = await ref.read(engineProvider.future);
    final result = await engine.executeTemplate('return sys.country()');
    // A bare string return fills `display`; trim any stray whitespace/newline.
    return result.display.trim();
  } catch (_) {
    return '';
  }
}

/// The live geo locator.
///
/// Resolved once per process (the locator caches internally), matching the C
/// `static int s_is_china = -1`.
final Provider<GeoLocator> geoLocatorProvider = Provider<GeoLocator>((Ref ref) {
  return GeoLocator(
    fetcher: ref.watch(httpFetcherProvider),
    osRegion: () => _osRegionFromEngine(ref),
    endpointOverride: Platform.environment[kGeoEndpointEnvVar],
  );
});
