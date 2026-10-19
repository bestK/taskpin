// Config loading/saving with debounced atomic writes.
//
// Mirrors the path policy of `lib/config.c:config_get_path` (exe-sibling
// `config.json`) for backward compatibility, and adds the portable-vs-roaming
// split agreed in docs/FLUTTER_REWRITE_PLAN.md:
//
//   Windows: exe-sibling `config.json` when present and writable (portable),
//            otherwise `%APPDATA%\TaskPin\config.json`
//   macOS:   `~/.taskpin/config.json`   (the legacy Swift location,
//            src/macos/Services/ConfigManager.swift:14-19)
//
// Writes are debounced and atomic (temp file + replace), matching the intent of
// `config_save` (lib/config.c:445-463) but not its silent failure mode.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config_schema.dart';
import 'migration.dart';

/// Where a config lives on this machine.
///
/// Resolved once at startup by [ConfigPaths.resolve] and then passed around, so
/// that the rest of the app never touches `Platform` or `%APPDATA%` directly.
class ConfigPaths {
  const ConfigPaths({
    required this.baseDir,
    required this.configFile,
    required this.scriptsDir,
    required this.portable,
    this.copiedFrom,
  });

  /// Directory containing [configFile].
  final String baseDir;

  /// Absolute path to `config.json`.
  final String configFile;

  /// Directory holding user-installed Lua scripts. The market downloads here
  /// (`mkt_download_script` writes next to the exe today).
  final String scriptsDir;

  /// True when [baseDir] is the executable's own directory.
  final bool portable;

  /// When a first run copied an existing portable install into
  /// `%APPDATA%\TaskPin\`, the directory it was copied from. Purely diagnostic.
  final String? copiedFrom;

  /// Sibling `config.ini`, the pre-JSON format that `config.c:344-357` migrates
  /// from. Retained so the Dart migration can honour the same legacy path.
  String get legacyIniFile => '$baseDir${Platform.pathSeparator}config.ini';

  /// Backup name for a migrated-away JSON config. The plan pins this name.
  String get legacyJsonBackup => '$baseDir${Platform.pathSeparator}config.v1.json';

  @override
  String toString() => 'ConfigPaths(base: $baseDir, portable: $portable)';

  /// Decides where the config lives.
  ///
  /// [executablePath], [environment] and [homeDirectory] are injectable so this
  /// is unit-testable against a temp directory without a real install.
  static ConfigPaths resolve({
    String? executablePath,
    Map<String, String>? environment,
    String? homeDirectory,
    bool? isWindows,
    bool? isMacOS,
  }) {
    final env = environment ?? Platform.environment;
    final exePath = executablePath ?? Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    final windows = isWindows ?? Platform.isWindows;
    final mac = isMacOS ?? Platform.isMacOS;

    if (mac) {
      final home = homeDirectory ?? env['HOME'] ?? exeDir;
      final base = _join(home, '.taskpin');
      return ConfigPaths(
        baseDir: base,
        configFile: _join(base, 'config.json'),
        scriptsDir: _join(base, 'scripts'),
        portable: false,
      );
    }

    if (windows) {
      return _resolveWindows(
        exeDir: exeDir,
        env: env,
      );
    }

    // Any other platform: keep everything next to the executable, which is the
    // least surprising fallback and keeps the tests platform-agnostic.
    return ConfigPaths(
      baseDir: exeDir,
      configFile: _join(exeDir, 'config.json'),
      scriptsDir: _join(exeDir, 'scripts'),
      portable: true,
    );
  }

  static ConfigPaths _resolveWindows({
    required String exeDir,
    required Map<String, String> env,
  }) {
    final portableConfig = _join(exeDir, 'config.json');
    final appDataRoot = env['APPDATA'] ?? env['LOCALAPPDATA'];
    if (appDataRoot == null || appDataRoot.isEmpty) {
      // No roaming profile (rare, e.g. a stripped service account). Stay
      // portable rather than inventing a path.
      return ConfigPaths(
        baseDir: exeDir,
        configFile: portableConfig,
        scriptsDir: _join(exeDir, 'scripts'),
        portable: true,
      );
    }

    final roamingDir = _join(appDataRoot, 'TaskPin');
    final roamingConfig = _join(roamingDir, 'config.json');

    // 1. Portable install wins when it is actually writable.
    if (File(portableConfig).existsSync() && _isWritableDir(exeDir)) {
      return ConfigPaths(
        baseDir: exeDir,
        configFile: portableConfig,
        scriptsDir: _join(exeDir, 'scripts'),
        portable: true,
      );
    }

    // 2. An existing roaming config wins next.
    if (File(roamingConfig).existsSync()) {
      return ConfigPaths(
        baseDir: roamingDir,
        configFile: roamingConfig,
        scriptsDir: _join(roamingDir, 'scripts'),
        portable: false,
      );
    }

    // 3. A portable config that we cannot write to (installed under Program
    //    Files) is adopted into the roaming directory, scripts and all.
    String? copiedFrom;
    if (File(portableConfig).existsSync()) {
      copiedFrom = exeDir;
      try {
        Directory(roamingDir).createSync(recursive: true);
        File(portableConfig).copySync(roamingConfig);
        final portableScripts = Directory(_join(exeDir, 'scripts'));
        if (portableScripts.existsSync()) {
          _copyDirectory(portableScripts, Directory(_join(roamingDir, 'scripts')));
        }
      } catch (_) {
        // Adoption is best-effort; a failure here still leaves a usable
        // (empty) roaming config rather than a crash at startup.
      }
    }

    return ConfigPaths(
      baseDir: roamingDir,
      configFile: roamingConfig,
      scriptsDir: _join(roamingDir, 'scripts'),
      portable: false,
      copiedFrom: copiedFrom,
    );
  }

  static String _join(String a, String b) {
    if (a.endsWith('/') || a.endsWith('\\')) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }

  /// Windows has no cheap `access(W_OK)`; probe by creating a real file.
  static bool _isWritableDir(String dir) {
    final probe = File(_join(dir, '.taskpin-write-probe'));
    try {
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      try {
        if (probe.existsSync()) probe.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  static void _copyDirectory(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(recursive: true)) {
      final name = entity.path.substring(from.path.length);
      final target = '${to.path}$name';
      if (entity is File) {
        File(target).parent.createSync(recursive: true);
        entity.copySync(target);
      } else if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      }
    }
  }
}

/// Loads and saves [TaskPinConfig].
///
/// Saving is debounced ([debounce], default 500ms) and coalesced, so the UI can
/// call [save] on every keystroke. Each flush is atomic: write `.tmp`, then
/// replace. Unlike `config_save`, failures are reported rather than swallowed.
class ConfigRepository {
  ConfigRepository({
    required this.paths,
    this.debounce = const Duration(milliseconds: 500),
    this.onError,
    bool autoMigrate = true,
  }) : _autoMigrate = autoMigrate;

  final ConfigPaths paths;
  final Duration debounce;

  /// Invoked for background write failures, which have no caller to throw to.
  final void Function(Object error, StackTrace stack)? onError;

  final bool _autoMigrate;

  TaskPinConfig? _current;
  Timer? _timer;
  String? _lastWritten;

  /// The most recently loaded or saved config, or null before the first load.
  TaskPinConfig? get current => _current;

  bool get hasPendingWrite => _timer?.isActive ?? false;

  /// Loads the config, migrating a legacy file first when necessary.
  ///
  /// Throws [ConfigVersionError] when the file declares a newer format; the
  /// file is left untouched in that case.
  Future<TaskPinConfig> load() async {
    if (_autoMigrate) {
      // Migration owns detection, backup and the rewrite; it is a no-op for a
      // file already in the unified format.
      await ConfigMigrator(paths: paths).migrateIfNeeded();
    }

    final file = File(paths.configFile);
    if (!file.existsSync()) {
      final fresh = TaskPinConfig();
      _current = fresh;
      return fresh;
    }

    final text = await file.readAsString(encoding: utf8);
    if (text.trim().isEmpty) {
      final fresh = TaskPinConfig();
      _current = fresh;
      return fresh;
    }

    final cfg = TaskPinConfig.fromJsonString(text, path: paths.configFile);
    _current = cfg;
    return cfg;
  }

  /// Schedules a debounced write. Safe to call from a UI event handler.
  void save(TaskPinConfig cfg) {
    _current = cfg;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      // A background failure has no caller to throw to, so it is reported
      // through onError. An unawaited future would otherwise surface as an
      // unhandled-error zone crash.
      _writeNow().catchError((Object e, StackTrace s) {
        onError?.call(e, s);
      });
    });
  }

  /// Writes immediately, cancelling any pending debounce.
  ///
  /// Call on window close and at the end of tests. Awaiting this guarantees the
  /// file on disk matches [current].
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    try {
      await _writeNow();
    } catch (e, s) {
      onError?.call(e, s);
      rethrow;
    }
  }

  /// Flushes and releases the timer.
  Future<void> dispose() async {
    if (hasPendingWrite || _current != null) {
      try {
        await flush();
      } catch (_) {
        // dispose must not throw; onError already reported it.
      }
    }
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _writeNow() async {
    final cfg = _current;
    if (cfg == null) return;

    final payload = cfg.toJsonString();

    // Skip a no-op write so that mtime does not churn (the C layer rewrites
    // unconditionally on every save, which defeats NTFS change detection).
    if (_lastWritten == payload && File(paths.configFile).existsSync()) return;

    final target = File(paths.configFile);
    target.parent.createSync(recursive: true);

    final tmp = File('${paths.configFile}.tmp');
    await tmp.writeAsString(payload, encoding: utf8, flush: true);

    // `File.rename` on Windows can refuse to replace an existing file, so fall
    // back to an explicit delete-and-retry. This is the same sequence the C
    // layer asks MoveFileEx for, spelled out.
    try {
      await tmp.rename(paths.configFile);
    } on FileSystemException {
      if (target.existsSync()) {
        await target.delete();
      }
      await tmp.rename(paths.configFile);
    }

    _lastWritten = payload;
  }
}
