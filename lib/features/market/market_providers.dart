// Providers for the plugin market page.
//
// The network goes through `httpFetcherProvider` and the proxy decision through
// `marketInChinaProvider`. Tests override both, so no test touches the network.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../core/market/geo_providers.dart';
import '../../core/market/http_fetcher.dart';
import '../../core/market/market_installer.dart';
import '../../core/market/market_models.dart';
import '../../core/market/market_source.dart';
import '../../core/market/market_sources.dart';
import '../../core/net/http_providers.dart';

/// Whether GitHub URLs go through gh-proxy. Falls back to false on any failure.
final FutureProvider<bool> marketInChinaProvider =
    FutureProvider<bool>((Ref ref) async {
  try {
    return await ref.watch(geoLocatorProvider).isInChina();
  } on Object {
    return false;
  }
});

/// The catalog of one source.
class MarketSourceCatalog {
  const MarketSourceCatalog({
    required this.repo,
    required this.scripts,
    this.error = '',
  });

  /// `user/repo`.
  final String repo;

  /// Usable scripts, in source order.
  final List<MarketScript> scripts;

  /// `network`, `api`, or a message. Empty when the fetch worked.
  final String error;

  bool get failed => error.isNotEmpty;
}

/// The catalogs of every configured source.
class MarketCatalog {
  const MarketCatalog({required this.sources, required this.inChina});

  final List<MarketSourceCatalog> sources;

  /// True when downloads go through gh-proxy.
  final bool inChina;

  int get scriptCount => sources.fold<int>(
        0,
        (int n, MarketSourceCatalog s) => n + s.scripts.length,
      );

  bool get allFailed =>
      sources.isNotEmpty && sources.every((MarketSourceCatalog s) => s.failed);
}

/// Fetches every source. Reloads when the source list changes; refresh with
/// `ref.invalidate(marketCatalogProvider)`.
final FutureProvider<MarketCatalog> marketCatalogProvider =
    FutureProvider<MarketCatalog>((Ref ref) async {
  // A joined string compares by value, so only a real change reloads.
  final List<String> repos = ref
      .watch(configProvider.select((TaskPinConfig c) => c.sources.join('\n')))
      .split('\n')
      .where((String s) => s.trim().isNotEmpty)
      .toList();
  final HttpFetcher fetcher = ref.watch(httpFetcherProvider);
  final bool inChina = await ref.watch(marketInChinaProvider.future);

  Future<MarketSourceCatalog> one(String repo) async {
    try {
      final MarketFetch fetch = await fetchMarketCatalog(
        repo,
        fetcher: fetcher,
        inChina: inChina,
      );
      return MarketSourceCatalog(
        repo: repo,
        scripts: fetch.scripts
            .where((MarketScript s) => s.isUsable)
            .toList(growable: false),
        error: fetch.error,
      );
    } on Object catch (e) {
      return MarketSourceCatalog(
        repo: repo,
        scripts: const <MarketScript>[],
        error: '$e',
      );
    }
  }

  final List<MarketSourceCatalog> sources =
      await Future.wait(repos.map(one));
  return MarketCatalog(sources: sources, inChina: inChina);
});

/// Opens a folder in the system file manager. Null where unsupported.
typedef FolderOpener = Future<void> Function(String directory);

/// The folder opener. Overridden in tests.
final Provider<FolderOpener?> scriptFolderOpenerProvider =
    Provider<FolderOpener?>((Ref ref) {
  if (Platform.isWindows) {
    return (String dir) async {
      await Process.start('explorer.exe', <String>[dir]);
    };
  }
  if (Platform.isMacOS) {
    return (String dir) async {
      await Process.start('open', <String>[dir]);
    };
  }
  return null;
});

/// Stable key of a script across sources.
String marketScriptKey(MarketScript s) => '${s.sourceRepo}/${s.file}';

/// Keys of the scripts being installed, and the install action.
final NotifierProvider<MarketInstallController, Set<String>>
    marketInstallProvider =
    NotifierProvider<MarketInstallController, Set<String>>(
  MarketInstallController.new,
);

class MarketInstallController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Downloads [script], adds the item and saves the config.
  Future<InstallResult> install(MarketScript script) async {
    final String key = marketScriptKey(script);
    if (state.contains(key)) {
      return const InstallResult(outcome: InstallOutcome.downloadFailed);
    }
    state = <String>{...state, key};
    try {
      final bool inChina = await ref.read(marketInChinaProvider.future);
      final repository = ref.read(configRepositoryProvider);
      final MarketInstaller installer = MarketInstaller(
        scriptsDir: repository.paths.scriptsDir,
        fetcher: ref.read(httpFetcherProvider),
        inChina: inChina,
        persist: () async {
          ref.read(configProvider.notifier).save();
          await repository.flush();
        },
      );
      return await installer.install(script, ref.read(configProvider));
    } finally {
      state = <String>{...state}..remove(key);
    }
  }
}

/// Adds [input] to the source list. Returns what happened.
SourceAddResult addMarketSource(WidgetRef ref, String input) {
  SourceAddResult result = SourceAddResult.empty;
  ref.read(configProvider.notifier).editGlobal((TaskPinConfig c) {
    result = addSource(c.sources, input);
  });
  return result;
}

/// Removes the source at [index].
void removeMarketSource(WidgetRef ref, int index) {
  ref.read(configProvider.notifier).editGlobal((TaskPinConfig c) {
    removeSourceAt(c.sources, index);
  });
}
