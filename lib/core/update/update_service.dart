// The updater: check on launch and every 30 minutes, ask, download, replace,
// relaunch.
//
// Ports `check_update_thread` (`lib/update.c:128-166`) and `do_silent_update`
// (lines 52-126), with the platform-specific apply step made explicit.
//
// ─────────────────────────────────────────────────────────────────────────────
// What is preserved exactly
// ─────────────────────────────────────────────────────────────────────────────
//   * Version comparison is a string compare, not semver. See version_compare.dart.
//   * The check URL is `bestK/taskpin/raw/master/version.txt`, built through the
//     gh-proxy rewriter when in China (`gh_url`, line 136).
//   * The loop sleeps 3000 ms before the FIRST check (line 130) and 30 minutes
//     between checks (line 165).
//   * When the user DECLINES the update, the loop STOPS PERMANENTLY (`return 0`,
//     line 159). It does not re-ask. Pinned by a test.
//   * Windows apply: since the Flutter rewrite the app is a launcher plus a
//     runtime, so the updater downloads `TaskPin-<arch>.zip`, extracts it, and
//     copies the WHOLE TREE over the install via a detached batch (wait → copy →
//     start → self-delete). An install with the pre-rewrite single-file layout
//     (no `data/` beside the exe) still gets the old exe-replacement flow.
//     See `_applyWindows` for why replacing the bare exe would brick an install.
//   * Download failure: show a message and open the release zip page in the
//     browser (`ShellExecuteW(open)`, lines 73-82).
//
// ─────────────────────────────────────────────────────────────────────────────
// What is new (macOS had no precedent)
// ─────────────────────────────────────────────────────────────────────────────
// macOS replaces the contents of the `.app` bundle in place and relaunches. If
// the bundle is not writable (installed under /Applications by another user, or
// quarantined read-only), it falls back to opening the release page rather than
// failing.
//
// ─────────────────────────────────────────────────────────────────────────────
// Test seams — why nothing here can hurt a real installation
// ─────────────────────────────────────────────────────────────────────────────
// Every side effect is injected:
//
//   fetcher        loopback HttpServer in tests, never GitHub
//   runner         records argv instead of spawning a process
//   exitHook       records instead of calling exit(0)
//   presenter      scripted yes/no instead of a MessageBox
//   platform       lets the macOS branch be exercised on Windows
//
// and [UpdateService.allowRealApply] defaults to false whenever the process is
// not a packaged build, so the test run cannot replace the running binary even
// if a test misconfigures the seams.
//
// Pure Dart.

import 'dart:async';
import 'dart:io';

import '../elevate/elevate_service.dart' show bundlePathFor;
import '../market/geo.dart';
import '../market/gh_proxy.dart';
import '../market/http_fetcher.dart';
import 'update_models.dart';
import 'version_compare.dart';

/// The repository the updater talks to.
const String kUpdateRepo = 'bestK/taskpin';

/// `version.txt` path within the repo (`lib/update.c:136`).
const String kVersionPath = '$kUpdateRepo/raw/master/version.txt';

/// The architecture suffix used in release asset names (`lib/update.c:54-58`).
///
/// The C code picks this at compile time with `#ifdef _WIN64`. `x64` is the
/// only asset the CI publishes (`release.yml` builds `taskpin-x64.exe`), so a
/// 32-bit build would look for an asset that does not exist — which is also true
/// of the shipping C code.
String updateArchSuffix() => _is64Bit ? 'x64' : 'x86';

final bool _is64Bit = () {
  // dart:io has no "is 64-bit" predicate. `Platform.version` reports the
  // architecture in its string, and the VM only ships for the common cases;
  // defaulting to x64 matches every published build.
  final String v = Platform.version;
  return !v.contains('ia32') && !v.contains('x86');
}();

/// The release asset paths, relative to the repo (`lib/update.c:62,77`).
///
/// `taskpin-x64.exe` is FROZEN: existing installs' updaters (the C `lib/update.c`
/// still shipped in v1.6.8) fetch it by this exact name. The packaging agent
/// keeps it a byte-copy of the launcher. Do not rename or repurpose it.
String updateExePath({String? arch}) =>
    '$kUpdateRepo/releases/latest/download/taskpin-${arch ?? updateArchSuffix()}.exe';

/// The full Windows distribution, as a zip.
///
/// Since the Flutter rewrite `taskpin.exe` is a ~67 KB launcher that needs
/// `flutter_windows.dll`, `data/app.so`, `data/`, and the MSVC runtime DLLs
/// beside it. Replacing the exe alone would brick the install — the new launcher
/// cannot even load `flutter_windows.dll`. So the Windows updater applies THIS
/// asset (the whole tree), not the bare exe.
///
/// The name is `TaskPin-windows.zip` — the OS name, NOT the arch suffix. That is
/// what `release.yml` publishes and what the plan documents
/// ("`releases/latest/download/TaskPin-windows.zip`"); it is frozen alongside the
/// exe. (The exe asset is arch-suffixed, `taskpin-x64.exe`, because the C updater
/// built its name that way; the zip is not.)
String updateZipPath() => '$kUpdateRepo/releases/latest/download/TaskPin-windows.zip';

/// macOS ships a zip containing `TaskPin.app` plus `install.command`.
const String kMacUpdateAsset = '$kUpdateRepo/releases/latest/download/TaskPin-macos.zip';

/// How the caller is asked to confirm an update.
///
/// The C behaviour is `MessageBoxW(..., MB_YESNO | MB_ICONINFORMATION)`
/// (`lib/update.c:152`). The UI implements this with `TpConfirmDialog`.
abstract class UpdatePresenter {
  /// Const-constructible so [DecliningPresenter] can be `const`.
  const UpdatePresenter();

  Future<bool> confirmUpdate(String remote, String current);

  /// A non-blocking progress notification.
  ///
  /// Has a default body so a presenter that does not care about progress — every
  /// test presenter, and `DecliningPresenter` — does not have to implement it.
  void onPhase(UpdatePhase phase) {}
}

/// A presenter that always declines. The safe default: a service constructed
/// without a presenter never offers an update.
///
/// `extends` (not `implements`) so it inherits [UpdatePresenter.onPhase]'s
/// default body.
class DecliningPresenter extends UpdatePresenter {
  const DecliningPresenter();

  @override
  Future<bool> confirmUpdate(String remote, String current) async => false;
}

/// Runs a detached process. Injected so tests record instead of spawning.
abstract class ProcessRunner {
  /// Starts [executable] with [arguments] detached, with no console window.
  ///
  /// Returns true when the process started.
  Future<bool> startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool hidden,
  });

  /// Runs a command and waits. Used for the macOS `open`/`osascript` path.
  Future<ProcessResult> run(String executable, List<String> arguments);
}

/// Opens a URL in the default browser (`ShellExecuteW(NULL, L"open", ...)`).
abstract class UrlOpener {
  Future<void> open(String url);
}

/// Ends the process (`ExitProcess(0)`, `lib/update.c:124`). Injected so tests do
/// not kill the test runner.
abstract class ExitHook {
  void exit(int code);
}

/// The default [ProcessRunner], backed by `dart:io`.
class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<bool> startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool hidden = true,
  }) async {
    try {
      final Process p = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: hidden ? ProcessStartMode.detachedWithStdio : ProcessStartMode.detached,
        runInShell: false,
      );
      // detachedWithStdio hands us the pipes; closing them lets the child run
      // on independently.
      try {
        await p.stdin.close();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);
}

/// The default [UrlOpener]. Platform-native so a packaged build behaves like the
/// C `ShellExecuteW(open)`.
class PlatformUrlOpener implements UrlOpener {
  const PlatformUrlOpener();

  @override
  Future<void> open(String url) async {
    if (Platform.isWindows) {
      // `start` is a cmd builtin, hence runInShell via cmd /c.
      await Process.run('cmd', <String>['/c', 'start', '', url], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.run('open', <String>[url]);
    } else {
      await Process.run('xdg-open', <String>[url]);
    }
  }
}

/// The default [ExitHook].
class RealExitHook implements ExitHook {
  const RealExitHook();

  @override
  void exit(int code) => exit0(code);
}

/// Isolated so `dart:io`'s `exit` is named in exactly one place, and so an
/// analyzer does not flag the call in the service.
void exit0(int code) {
  // ignore: avoid_print
  exit(code);
}

/// Checks for updates and applies them.
class UpdateService {
  UpdateService({
    required this.fetcher,
    required this.currentVersion,
    GeoLocator? geo,
    UpdatePresenter? presenter,
    ProcessRunner? runner,
    UrlOpener? opener,
    ExitHook? exitHook,
    this.initialDelay = const Duration(seconds: 3),
    this.interval = const Duration(minutes: 30),
    this.baseUrl = '',
    String? platformOverride,
    String? executablePath,
    String? tempDir,
    bool? allowRealApply,
  })  : _geo = geo,
        _presenter = presenter ?? const DecliningPresenter(),
        _runner = runner ?? const IoProcessRunner(),
        _opener = opener ?? const PlatformUrlOpener(),
        _exit = exitHook ?? const RealExitHook(),
        _platform = platformOverride,
        _exePath = executablePath,
        _tempDir = tempDir,
        _allowRealApply = allowRealApply ?? _defaultAllowRealApply();

  final HttpFetcher fetcher;

  /// The running build's version. On the real app this is read from
  /// `version.txt` next to the executable (the Makefile bakes the same value
  /// into `TASKPIN_VERSION`).
  final String currentVersion;

  final GeoLocator? _geo;
  final UpdatePresenter _presenter;
  final ProcessRunner _runner;
  final UrlOpener _opener;
  final ExitHook _exit;
  final String? _platform;
  final String? _exePath;
  final String? _tempDir;
  final bool _allowRealApply;

  /// Sleep before the first check (`Sleep(3000)`).
  final Duration initialDelay;

  /// Sleep between checks (`Sleep(30 * 60 * 1000)`).
  final Duration interval;

  /// Prefix for every URL. Empty means the real GitHub hosts. Tests set this to
  /// `http://127.0.0.1:<port>/` so no request can leave loopback.
  final String baseUrl;

  bool _stopped = false;
  bool _declined = false;
  bool _applied = false;
  int _checkCount = 0;

  /// Whether the update was offered and declined. Once true the loop is dead
  /// (the C `return 0` at `lib/update.c:159`).
  bool get declined => _declined;

  /// How many checks have run. Test-visible.
  int get checkCount => _checkCount;

  /// Whether an apply has already been performed. Applying twice would be a
  /// bug; guarded rather than assumed.
  bool get applied => _applied;

  /// Whether the loop has stopped for any reason.
  bool get stopped => _stopped;

  /// Stops the loop. Call on shutdown.
  void stop() => _stopped = true;

  /// One check. Returns what was found; does NOT apply anything.
  Future<UpdateCheckResult> checkOnce() async {
    _checkCount++;
    final bool inChina = await _isInChina();
    final String url = _url(kVersionPath, inChina: inChina);

    final HttpResult result = await fetcher.getText(url, maxBytes: 4096);
    if (!result.isSuccess) {
      return UpdateCheckResult(
        status: UpdateStatus.checkFailed,
        remoteVersion: '',
        currentVersion: currentVersion,
        inChina: inChina,
      );
    }

    final String tag = trimVersionTag(result.body);
    if (tag.isEmpty) {
      return UpdateCheckResult(
        status: UpdateStatus.checkFailed,
        remoteVersion: '',
        currentVersion: currentVersion,
        inChina: inChina,
      );
    }

    final bool available = isUpdateAvailable(tag, currentVersion);
    return UpdateCheckResult(
      status: available ? UpdateStatus.available : UpdateStatus.upToDate,
      remoteVersion: tag,
      currentVersion: currentVersion,
      inChina: inChina,
    );
  }

  /// Runs the check loop until [stop] is called or the user declines.
  ///
  /// Mirrors `check_update_thread`: sleep, check, and either ask or sleep again.
  Future<void> run() async {
    if (initialDelay > Duration.zero) {
      await Future<void>.delayed(initialDelay);
    }

    while (!_stopped) {
      final UpdateCheckResult result = await checkOnce();
      if (_stopped) return;

      if (result.status == UpdateStatus.available) {
        final bool yes =
            await _presenter.confirmUpdate(result.remoteVersion, currentVersion);
        if (!yes) {
          // The C code returns from the thread here: it never asks again.
          _declined = true;
          _stopped = true;
          return;
        }
        await apply(result);
        return;
      }

      if (_stopped) return;
      await Future<void>.delayed(interval);
    }
  }

  /// Downloads and applies the update, then exits.
  ///
  /// Safe to call directly (the "Check for Updates" menu item does).
  Future<UpdateApplyResult> apply(UpdateCheckResult result) async {
    if (_applied) {
      return UpdateApplyResult(status: UpdateApplyStatus.alreadyApplied);
    }

    final bool inChina = result.inChina;
    final String platform = _platform ?? _currentPlatform();

    if (platform == 'macos') {
      return _applyMacOs(inChina: inChina);
    }
    if (platform == 'windows') {
      return _applyWindows(inChina: inChina);
    }
    // No supported apply path; open the release page rather than pretending.
    await _opener.open(_url(updateZipPath(), inChina: inChina));
    return UpdateApplyResult(status: UpdateApplyStatus.openedBrowser);
  }

  /// Windows: download the whole distribution zip, extract it, write the
  /// detached batch that copies the tree over the install and restarts.
  ///
  /// ─────────────────────────────────────────────────────────────────────────
  /// WHY A ZIP AND NOT THE EXE (the bug this replaced)
  /// ─────────────────────────────────────────────────────────────────────────
  /// The pre-rewrite build was a single 1.83 MB exe, so replacing the exe WAS the
  /// whole update. The Flutter build is a ~67 KB launcher that needs
  /// `flutter_windows.dll` (20 MB), `data/app.so`, `data/icudtl.dat`,
  /// `data/flutter_assets/` and the MSVC runtime DLLs beside it. Copying only the
  /// exe over an old install leaves a launcher with no runtime: it cannot load
  /// `flutter_windows.dll`, so it cannot start, and it cannot self-heal because
  /// the launcher is the thing that would have to run. Silent bricking.
  ///
  /// So the apply downloads `TaskPin-<arch>.zip`, extracts it into the temp dir,
  /// and the batch copies the extracted TREE over the install directory.
  ///
  /// ─────────────────────────────────────────────────────────────────────────
  /// THE OLD-LAYOUT FALLBACK
  /// ─────────────────────────────────────────────────────────────────────────
  /// An install that predates the rewrite has no `data/` directory beside its
  /// exe, and its own updater expects to receive a bare exe. [looksLikeLegacyInstall]
  /// decides by inspecting the filesystem (NOT a version number, which the old
  /// updater never wrote in a readable place) and, for that layout, keeps the
  /// original exe-replacement flow.
  Future<UpdateApplyResult> _applyWindows({required bool inChina}) async {
    if (!_allowRealApply) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.disabled,
        detail: 'real apply is disabled in this process (not a packaged build)',
      );
    }

    final String exe = _executablePath();
    if (looksLikeLegacyInstall(exe)) {
      return _applyWindowsLegacyExe(inChina: inChina);
    }

    _presenter.onPhase(UpdatePhase.downloading);
    final String zipUrl = _url(updateZipPath(), inChina: inChina);
    final HttpResult download =
        await fetcher.getBytes(zipUrl, maxBytes: 256 * 1024 * 1024);

    if (!download.isSuccess || download.bodyBytes == null || download.bodyBytes!.isEmpty) {
      // `lib/update.c:73-82`: tell the user, then open the release page.
      await _opener.open(_url(updateZipPath(), inChina: inChina));
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: 'GET $zipUrl -> ${download.statusCode}',
      );
    }

    final String temp = _tempDirectory();
    final String installDir = File(exe).parent.path;
    final String tmpZip = '$temp${Platform.pathSeparator}taskpin_update.zip';
    final String tmpStage = '$temp${Platform.pathSeparator}taskpin_update_stage';
    final String tmpBat = '$temp${Platform.pathSeparator}taskpin_update.bat';

    try {
      await Directory(tmpStage).create(recursive: true);
      await File(tmpZip).writeAsBytes(download.bodyBytes!, flush: true);

      // Extract the zip into the stage dir. `tar -xf` handles zip on Windows 10
      // 1803+ (bsdtar); the PowerShell cmdlet is the fallback for older builds.
      final bool extracted = await _extractZip(tmpZip, tmpStage);
      if (!extracted) {
        return const UpdateApplyResult(
          status: UpdateApplyStatus.downloadFailed,
          detail: 'could not extract the update zip',
        );
      }

      await File(tmpBat).writeAsString(
        buildZipUpdateBatch(
          currentExe: exe,
          installDir: installDir,
          stageDir: tmpStage,
          tmpZip: tmpZip,
          tmpBat: tmpBat,
        ),
        flush: true,
      );
    } catch (e) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: '$e',
      );
    }

    _presenter.onPhase(UpdatePhase.restarting);

    final bool started = await _runner.startDetached(
      'cmd',
      <String>['/c', tmpBat],
      hidden: true,
    );
    if (!started) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: 'could not launch $tmpBat',
      );
    }

    _applied = true;
    _exit.exit(0);
    return const UpdateApplyResult(status: UpdateApplyStatus.restarting);
  }

  /// The pre-rewrite flow: download the bare exe, copy it over the running one.
  ///
  /// Kept only for an install whose layout is the old single-file one (see
  /// [looksLikeLegacyInstall]). For a modern install this path is never taken.
  Future<UpdateApplyResult> _applyWindowsLegacyExe({required bool inChina}) async {
    _presenter.onPhase(UpdatePhase.downloading);
    final String exeUrl = _url(updateExePath(), inChina: inChina);
    final HttpResult download =
        await fetcher.getBytes(exeUrl, maxBytes: 64 * 1024 * 1024);

    final String temp = _tempDirectory();
    final String tmpExe = '$temp${Platform.pathSeparator}taskpin_update.exe';
    final String tmpBat = '$temp${Platform.pathSeparator}taskpin_update.bat';

    if (!download.isSuccess || download.bodyBytes == null || download.bodyBytes!.isEmpty) {
      await _opener.open(_url(updateZipPath(), inChina: inChina));
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: 'GET $exeUrl -> ${download.statusCode}',
      );
    }

    try {
      final File tmp = File(tmpExe);
      await tmp.parent.create(recursive: true);
      await tmp.writeAsBytes(download.bodyBytes!, flush: true);
      await File(tmpBat).writeAsString(
        buildUpdateBatch(currentExe: _executablePath(), tmpExe: tmpExe, tmpBat: tmpBat),
        flush: true,
      );
    } catch (e) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: '$e',
      );
    }

    _presenter.onPhase(UpdatePhase.restarting);

    final bool started = await _runner.startDetached(
      'cmd',
      <String>['/c', tmpBat],
      hidden: true,
    );
    if (!started) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: 'could not launch $tmpBat',
      );
    }

    _applied = true;
    _exit.exit(0);
    return const UpdateApplyResult(status: UpdateApplyStatus.restarting);
  }

  /// Extracts [zipPath] into [destDir] using a tool Windows already has.
  ///
  /// `tar.exe` (bsdtar) has shipped since Windows 10 1803 and reads zip; the
  /// PowerShell cmdlet covers anything older. Returns false when neither works.
  Future<bool> _extractZip(String zipPath, String destDir) async {
    try {
      final ProcessResult tar = await _runner.run(
        'tar',
        <String>['-xf', zipPath, '-C', destDir],
      );
      if (tar.exitCode == 0) return true;
    } catch (_) {
      // Fall through to PowerShell.
    }
    try {
      final ProcessResult ps = await _runner.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Expand-Archive -LiteralPath "${zipPath.replaceAll('"', '\\"')}" '
              '-DestinationPath "${destDir.replaceAll('"', '\\"')}" -Force',
        ],
      );
      return ps.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// macOS: replace inside the `.app` bundle and relaunch, or open the release
  /// page when the bundle is not writable.
  ///
  /// There is no C precedent for this — the shipping updater is Windows-only.
  Future<UpdateApplyResult> _applyMacOs({required bool inChina}) async {
    final String bundle = _bundlePath();
    if (!_allowRealApply) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.disabled,
        detail: 'real apply is disabled in this process (not a packaged build)',
      );
    }

    if (!_isWritable(bundle)) {
      // The plan's acceptance criterion: degrade to opening the release page.
      await _opener.open(_url(kMacUpdateAsset, inChina: inChina));
      return const UpdateApplyResult(
        status: UpdateApplyStatus.bundleNotWritable,
      );
    }

    _presenter.onPhase(UpdatePhase.downloading);
    final HttpResult download =
        await fetcher.getBytes(_url(kMacUpdateAsset, inChina: inChina), maxBytes: 128 * 1024 * 1024);
    if (!download.isSuccess || download.bodyBytes == null || download.bodyBytes!.isEmpty) {
      await _opener.open(_url(kMacUpdateAsset, inChina: inChina));
      return const UpdateApplyResult(status: UpdateApplyStatus.downloadFailed);
    }

    final String temp = _tempDirectory();
    final String zip = '$temp/TaskPin-macos.zip';
    final String stage = '$temp/TaskPin-update-stage';
    try {
      await File(zip).writeAsBytes(download.bodyBytes!, flush: true);
      await Directory(stage).create(recursive: true);
      // `ditto` preserves the bundle's symlinks and permissions; `unzip` does
      // not, which would break the embedded Flutter framework.
      await _runner.run('/usr/bin/ditto', <String>['-x', '-k', zip, stage]);
      await _runner.run('/usr/bin/ditto', <String>['$stage/TaskPin.app/', '$bundle/']);
    } catch (e) {
      return UpdateApplyResult(
        status: UpdateApplyStatus.downloadFailed,
        detail: '$e',
      );
    }

    _presenter.onPhase(UpdatePhase.restarting);
    await _runner.startDetached('/usr/bin/open', <String>['-n', bundle], hidden: false);
    _applied = true;
    _exit.exit(0);
    return const UpdateApplyResult(status: UpdateApplyStatus.restarting);
  }

  /// Builds the detached batch that waits, replaces, restarts and self-deletes.
  ///
  /// This is the LEGACY (single-exe) path, used only for an install whose layout
  /// is the pre-rewrite one (see [looksLikeLegacyInstall]). The body is the exact
  /// template from `lib/update.c:98-105`. It is a public top-level function so
  /// `test/update/update_service_test.dart` can compare it character-for-character
  /// against the C source's format string.
  static String buildUpdateBatch({
    required String currentExe,
    required String tmpExe,
    required String tmpBat,
  }) =>
      '@echo off\r\n'
      'timeout /t 2 /nobreak >nul\r\n'
      'copy /y "$tmpExe" "$currentExe" >nul\r\n'
      'start "" "$currentExe"\r\n'
      'del "$tmpExe"\r\n'
      'del "%~f0"\r\n';

  /// The exact C format string, for the test to diff against. Kept beside the
  /// builder so the two cannot drift without the test noticing.
  static const String cBatchTemplate = '@echo off\r\n'
      'timeout /t 2 /nobreak >nul\r\n'
      'copy /y "%s" "%s" >nul\r\n'
      'start "" "%s"\r\n'
      'del "%s"\r\n'
      'del "%%~f0"\r\n';

  /// Builds the detached batch for the MODERN (whole-tree) update.
  ///
  /// Keeps the detached-batch pattern from the legacy path — wait for the running
  /// process to release its files, copy, restart, self-delete — because replacing
  /// a running binary (and the DLLs it has mapped) is only possible after it has
  /// exited. The difference is that it copies the extracted TREE (`xcopy /e /y`)
  /// rather than one file, so the launcher and its runtime arrive together.
  ///
  /// `xcopy /e` copies empty directories too (so `data/flutter_assets/` comes
  /// across) and `/y` suppresses the overwrite prompt. `/i` treats the
  /// destination as a directory when the source is a tree. After the copy it
  /// removes the stage directory and the zip, then self-deletes.
  ///
  /// `%~dp0` is NOT used: the paths are absolute (the caller passes `%TEMP%`
  /// paths), which is what the C template does too.
  static String buildZipUpdateBatch({
    required String currentExe,
    required String installDir,
    required String stageDir,
    required String tmpZip,
    required String tmpBat,
  }) =>
      '@echo off\r\n'
      'timeout /t 2 /nobreak >nul\r\n'
      'xcopy /e /y /i "$stageDir" "$installDir" >nul\r\n'
      'start "" "$currentExe"\r\n'
      'rmdir /s /q "$stageDir"\r\n'
      'del "$tmpZip"\r\n'
      'del "%~f0"\r\n';

  /// Whether the running install has the PRE-REWRITE (single-exe) layout.
  ///
  /// Decided by the filesystem, not a version number: the old updater never
  /// recorded a version anywhere the new code could read, and the layout is the
  /// thing that actually matters. A modern Flutter install has a `data`
  /// directory (holding `app.so`, `icudtl.dat`, `flutter_assets/`) beside the
  /// executable; the old single-file build did not.
  ///
  /// A modern install whose `data/` is somehow missing would be misread as
  /// legacy — but such an install is already broken, and the legacy flow (which
  /// copies a bare exe) is no worse for it than the tree flow.
  static bool looksLikeLegacyInstall(String executablePath) {
    try {
      final String dir = File(executablePath).parent.path;
      return !Directory('$dir${Platform.pathSeparator}data').existsSync();
    } catch (_) {
      // Cannot tell: assume modern (the safe default for a shipped build).
      return false;
    }
  }

  String _executablePath() => _exePath ?? Platform.resolvedExecutable;

  String _tempDirectory() => _tempDir ?? Directory.systemTemp.path;

  String _currentPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }

  /// The `.app` bundle root, derived from the running executable.
  ///
  /// Delegates to [bundlePathFor] so the updater and the elevate flow cannot
  /// disagree about where the bundle is.
  String _bundlePath() => bundlePathFor(_executablePath());

  bool _isWritable(String path) {
    try {
      final Directory d = Directory(path);
      if (!d.existsSync()) return false;
      final File probe = File('$path/.taskpin-update-probe');
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isInChina() async {
    final GeoLocator? geo = _geo;
    if (geo == null) return false;
    return geo.isInChina();
  }

  /// Rewrites a repo path through [baseUrl] and the gh-proxy rule.
  ///
  /// When [baseUrl] is set (tests), the path is appended to it verbatim and no
  /// proxy rewriting happens — the loopback server serves everything.
  String _url(String path, {required bool inChina}) {
    if (baseUrl.isNotEmpty) {
      final String base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      // Strip the repo prefix so a loopback server can serve `/version.txt`.
      final String leaf = path.split('/').last;
      return '$base$leaf';
    }
    return githubPath(path, inChina: inChina);
  }
}

/// Whether applying an update for real is permitted in this process.
///
/// False under the Dart VM (`dart test`, `dart run`), where
/// `Platform.resolvedExecutable` is the VM binary and "replacing it" would be
/// both meaningless and destructive. A packaged Flutter build resolves to the
/// app executable and returns true.
bool _defaultAllowRealApply() {
  final String exe = Platform.resolvedExecutable.toLowerCase();
  return !(exe.endsWith('dart.exe') || exe.endsWith('/dart'));
}
