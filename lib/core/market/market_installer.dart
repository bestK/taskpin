// Installing a market script: download to `scripts/`, then ADD THE ITEM TO THE
// CONFIG AND SAVE IT.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE BUG THIS FILE EXISTS TO NOT LOSE
// ─────────────────────────────────────────────────────────────────────────────
// The old market's download button wrote the `.lua` file into `scripts/` and
// then stopped. It never touched `g_cfg`, so nothing appeared in the item list
// and `config.json` was unchanged — while the status line already read
// `market.download_success` ("下载并添加成功"). The button lied.
//
// Commit 4f5165c ("fix: market download adds item to config") fixed it in
// `src/ui_market_view.cpp` — the Dear ImGui view, NOT `src/market_dialog.c`,
// which still has the original bug (its `mkt_download_script` writes the file
// and returns). The C fix does five things, all reproduced here:
//
//   1. Add (or update) an `ITEM_TYPE_LUA` entry pointing at the downloaded file.
//   2. Name it from the manifest, falling back to the filename.
//   3. Seed `interval_ms` from `@refresh`, clamped to a 1000 ms floor, else 5000.
//   4. Seed `params` from the `@param` declarations, PRESERVING any values the
//      user had already filled in when re-downloading an existing script.
//   5. Save the config.
//
// A secondary defect in that same C path is fixed here: when the item list is
// already at `CFG_MAX_ITEMS`, the C code returns early and still reports
// `market.download_success`, so the user is told an install worked when nothing
// was added. We keep the downloaded file (it is genuinely on disk and the user
// may add the item by hand) but report [InstallOutcome.itemLimitReached].
//
// The invariant that must hold on every path, asserted by
// `test/market/market_installer_test.dart`:
//
//     IF the outcome is `installed` or `updated`, THEN the item is present in
//     the config AND the config was persisted.
//
// Pure Dart (`dart:io` for file writes). No Flutter.

import 'dart:io';

import '../config/config_schema.dart';
import 'gh_proxy.dart';
import 'http_fetcher.dart';
import 'market_models.dart';
import 'script_header.dart';

/// What an install attempt did.
enum InstallOutcome {
  /// A new item was added and the config saved.
  installed,

  /// An existing item for this file was updated and the config saved.
  updated,

  /// The `.lua` file was written but no item could be added because the item
  /// list is at [ConfigLimits.maxItems]. The config was NOT changed.
  itemLimitReached,

  /// The download failed (transport failure or non-2xx). Nothing was written.
  downloadFailed,

  /// The download succeeded but the file could not be written. The config was
  /// NOT changed.
  saveFailed,
}

/// The result of an install attempt.
class InstallResult {
  const InstallResult({
    required this.outcome,
    this.itemIndex = -1,
    this.filePath = '',
    this.message = '',
  });

  final InstallOutcome outcome;

  /// Index of the added/updated item in `config.items`, or -1 when none.
  final int itemIndex;

  /// Absolute path the script was (or would have been) written to.
  final String filePath;

  /// A diagnostic detail. Not user-facing text — the UI maps [outcome] to a
  /// localized string.
  final String message;

  /// True when the config was modified and saved. This is the flag the UI must
  /// key "it worked" off, rather than off the absence of an exception.
  bool get configChanged =>
      outcome == InstallOutcome.installed || outcome == InstallOutcome.updated;

  /// True when the file is on disk, whether or not an item was added.
  bool get fileWritten =>
      outcome == InstallOutcome.installed ||
      outcome == InstallOutcome.updated ||
      outcome == InstallOutcome.itemLimitReached;

  @override
  String toString() => 'InstallResult(${outcome.name}, idx: $itemIndex, $filePath)';
}

/// The `@refresh` floor the C fix applies: `if (refresh_ms < 1000)
/// refresh_ms = 5000;`
const int kMinRefreshMs = 1000;
const int kDefaultRefreshMs = 5000;

/// Downloads a market script and wires it into the config.
///
/// Construct with [scriptsDir] and [persist]. [persist] is the only way this
/// class writes to disk config-wise, which is what makes the "item added AND
/// saved" invariant testable with a counter instead of a real repository.
class MarketInstaller {
  MarketInstaller({
    required this.scriptsDir,
    required this.fetcher,
    required this.persist,
    required this.inChina,
  });

  /// Where `.lua` files land. `ConfigPaths.scriptsDir` on the real app: the exe
  /// sibling `scripts/` on Windows, `~/.taskpin/scripts` on macOS.
  final String scriptsDir;

  final HttpFetcher fetcher;

  /// Called after the config has been mutated, to write it out. Must complete
  /// before [install] returns so a caller can rely on the file being on disk.
  final Future<void> Function() persist;

  /// From [GeoLocator].
  final bool inChina;

  /// Downloads [script] and adds/updates its item in [config].
  ///
  /// [config] is mutated in place, matching the C layer's `g_cfg`. Call
  /// [persist] (via this method) rather than saving separately, so the invariant
  /// holds in one place.
  Future<InstallResult> install(MarketScript script, TaskPinConfig config) async {
    if (!script.isUsable) {
      return InstallResult(
        outcome: InstallOutcome.downloadFailed,
        message: 'not a .lua file: "${script.file}"',
      );
    }

    // ── 1. Download ─────────────────────────────────────────────────────────
    final String url = rawGithubPath(
      '${script.sourceRepo}/master/${script.file}',
      inChina: inChina,
    );
    final HttpResult result = await fetcher.getBytes(url, maxBytes: 4 * 1024 * 1024);

    if (!result.isSuccess || result.bodyBytes == null || result.bodyBytes!.isEmpty) {
      return InstallResult(
        outcome: InstallOutcome.downloadFailed,
        filePath: _targetPath(script.file),
        message: 'GET $url -> ${result.statusCode}',
      );
    }

    // ── 2. Write the file ───────────────────────────────────────────────────
    final String path = _targetPath(script.file);
    try {
      final Directory dir = Directory(scriptsDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File(path).writeAsBytes(result.bodyBytes!, flush: true);
    } catch (e) {
      return InstallResult(
        outcome: InstallOutcome.saveFailed,
        filePath: path,
        message: '$e',
      );
    }

    // ── 3. Find an existing item for this file ──────────────────────────────
    final int existing = _findExistingItem(config, script.file);

    if (existing < 0 && config.items.length >= ConfigLimits.maxItems) {
      // The file is on disk; no item can be added. Report honestly.
      return InstallResult(
        outcome: InstallOutcome.itemLimitReached,
        filePath: path,
        message: 'item list is at CFG_MAX_ITEMS (${ConfigLimits.maxItems})',
      );
    }

    final PinItem item;
    if (existing >= 0) {
      item = config.items[existing];
    } else {
      item = PinItem(
        type: PinItemType.lua,
        // The C fix's defaults for a fresh entry.
        barX: -1,
        barY: -1,
        barBgColor: kColorUseGlobal,
      );
      config.items.add(item);
    }

    // ── 4. Populate ─────────────────────────────────────────────────────────
    item.type = PinItemType.lua;
    item.luaPath = path;
    // Name from the manifest, falling back to the filename.
    item.name = script.name.isNotEmpty ? script.name : script.file;

    final String source = await _readScript(path);
    final int refresh = parseScriptRefresh(source);
    item.intervalMs = refresh < kMinRefreshMs ? kDefaultRefreshMs : refresh;

    _seedParams(item, await parseScriptParamsFile(path, maxDecls: ConfigLimits.maxParams));

    // ── 5. Persist ──────────────────────────────────────────────────────────
    await persist();

    final int index = existing >= 0 ? existing : config.items.length - 1;
    return InstallResult(
      outcome: existing >= 0 ? InstallOutcome.updated : InstallOutcome.installed,
      itemIndex: index,
      filePath: path,
    );
  }

  /// Absolute path a script file installs to.
  String _targetPath(String file) {
    final String sep = Platform.pathSeparator;
    final String base =
        scriptsDir.endsWith(sep) || scriptsDir.endsWith('/') ? scriptsDir : '$scriptsDir$sep';
    return '$base$file';
  }

  /// Index of an existing Lua item pointing at [file], or -1.
  ///
  /// Matches on BASENAME, case-insensitively. The C fix compares the full
  /// `lua_path` with `lstrcmpiW`, which misses when the same script was
  /// installed to a different directory (portable vs roaming — see
  /// `ConfigPaths.resolve`). Basename matching is the intent: "is this script
  /// already in the list?".
  int _findExistingItem(TaskPinConfig config, String file) {
    final String want = _basename(file).toLowerCase();
    for (int i = 0; i < config.items.length; i++) {
      final PinItem it = config.items[i];
      if (it.type != PinItemType.lua) continue;
      if (_basename(it.luaPath).toLowerCase() == want) return i;
    }
    return -1;
  }

  /// Replaces [item]'s params with the declarations from the file, carrying over
  /// any value the user had already entered for a matching key.
  ///
  /// This is the C fix's `old[]`/`memcpy` dance, which exists so that
  /// re-downloading an updated script does not silently wipe a saved API token.
  void _seedParams(PinItem item, List<ScriptParamDecl> decls) {
    final Map<String, String> previous = <String, String>{
      for (final ParamEntry p in item.params) p.key: p.value,
    };

    final List<ParamEntry> next = <ParamEntry>[];
    for (final ScriptParamDecl d in decls) {
      next.add(
        ParamEntry(
          key: d.key,
          label: d.label,
          value: previous[d.key] ?? '',
        ),
      );
    }
    item.params = next;
  }

  Future<String> _readScript(String path) async {
    try {
      final File f = File(path);
      if (!f.existsSync()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }
}

/// The final path component of a Windows or POSIX path.
String _basename(String path) {
  final int slash = path.lastIndexOf('/');
  final int backslash = path.lastIndexOf('\\');
  final int cut = slash > backslash ? slash : backslash;
  return cut >= 0 ? path.substring(cut + 1) : path;
}
