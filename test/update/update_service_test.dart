// The Windows updater: the whole-tree (zip) apply, the legacy single-exe
// fallback, and the batch templates.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE BUG THIS SUITE PINS
// ─────────────────────────────────────────────────────────────────────────────
// The pre-rewrite build was one 1.83 MB exe, so replacing the exe was the whole
// update. The Flutter build is a ~67 KB launcher that needs `flutter_windows.dll`,
// `data/app.so`, `data/` and the MSVC runtime DLLs beside it. Copying only the
// exe over an old install produces a launcher with no runtime: it cannot load
// `flutter_windows.dll`, cannot start, and cannot self-heal. So the modern apply
// MUST download the whole `TaskPin-windows.zip` and copy the tree.
//
// The legacy single-exe flow is kept only for an install whose layout is the old
// one, decided by inspecting the filesystem (`data/` present = modern), never by
// a version number.
//
// These are `dart:io` tests (temp directories, file writes); every side effect of
// the service is injected so nothing real is downloaded, launched or replaced.

import 'dart:io';

import 'package:taskpin/core/update/update_models.dart';
import 'package:taskpin/core/update/update_service.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

/// Records `startDetached`/`run` instead of spawning processes.
class FakeRunner implements ProcessRunner {
  final List<List<String>> started = <List<String>>[];
  final List<List<String>> ran = <List<String>>[];

  /// Exit code returned by [run] (tar / powershell / ditto).
  int runExitCode = 0;

  @override
  Future<bool> startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool hidden = true,
  }) async {
    started.add(<String>[executable, ...arguments]);
    return true;
  }

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    ran.add(<String>[executable, ...arguments]);
    return ProcessResult(0, runExitCode, '', '');
  }
}

class RecordingOpener implements UrlOpener {
  final List<String> opened = <String>[];
  @override
  Future<void> open(String url) async => opened.add(url);
}

class RecordingExit implements ExitHook {
  final List<int> codes = <int>[];
  @override
  void exit(int code) => codes.add(code);
}

void main() {
  late Directory root;
  late FakeFetcher fetcher;
  late FakeRunner runner;
  late RecordingOpener opener;
  late RecordingExit exitHook;

  setUp(() {
    root = Directory.systemTemp.createTempSync('taskpin_update_test_');
    fetcher = FakeFetcher();
    runner = FakeRunner();
    opener = RecordingOpener();
    exitHook = RecordingExit();
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Builds a service rooted at a fake install whose layout is [modern].
  ///
  /// A modern install has a `data/` directory beside the exe; a legacy one does
  /// not. Both are real directories on disk so `looksLikeLegacyInstall` inspects
  /// the truth.
  UpdateService service({required bool modern, String? platform = 'windows'}) {
    final String install = '${root.path}${Platform.pathSeparator}install';
    Directory(install).createSync(recursive: true);
    final String exe = '$install${Platform.pathSeparator}taskpin.exe';
    File(exe).writeAsStringSync('launcher');
    if (modern) {
      Directory('$install${Platform.pathSeparator}data').createSync();
      File('$install${Platform.pathSeparator}data${Platform.pathSeparator}app.so')
          .writeAsStringSync('snapshot');
    }
    final String temp = '${root.path}${Platform.pathSeparator}tmp';
    Directory(temp).createSync(recursive: true);
    return UpdateService(
      fetcher: fetcher,
      currentVersion: '1.6.8',
      runner: runner,
      opener: opener,
      exitHook: exitHook,
      allowRealApply: true,
      platformOverride: platform,
      executablePath: exe,
      tempDir: temp,
    );
  }

  const UpdateCheckResult available = UpdateCheckResult(
    status: UpdateStatus.available,
    remoteVersion: '1.7.0',
    currentVersion: '1.6.8',
  );

  group('asset names are frozen', () {
    test('the exe asset is taskpin-x64.exe (old installs depend on it)', () {
      expect(updateExePath(), endsWith('taskpin-x64.exe'));
    });

    test('the zip asset is TaskPin-windows.zip (OS name, not arch-suffixed)', () {
      expect(updateZipPath(), endsWith('TaskPin-windows.zip'));
    });
  });

  group('layout detection', () {
    test('a modern install (data/ present) is NOT legacy', () {
      final UpdateService s = service(modern: true);
      expect(
        UpdateService.looksLikeLegacyInstall(
          '${root.path}${Platform.pathSeparator}install'
          '${Platform.pathSeparator}taskpin.exe',
        ),
        isFalse,
      );
      expect(s, isNotNull);
    });

    test('a legacy install (no data/) IS legacy', () {
      final UpdateService s = service(modern: false);
      expect(
        UpdateService.looksLikeLegacyInstall(
          '${root.path}${Platform.pathSeparator}install'
          '${Platform.pathSeparator}taskpin.exe',
        ),
        isTrue,
      );
      expect(s, isNotNull);
    });
  });

  group('the modern (whole-tree) apply', () {
    test('downloads the zip, extracts it, and writes a tree-copy batch', () async {
      fetcher.onBytes('/TaskPin-windows.zip', <int>[80, 75, 3, 4]);
      final UpdateService s = service(modern: true);

      final UpdateApplyResult result = await s.apply(available);

      expect(result.status, UpdateApplyStatus.restarting);
      // It fetched the ZIP, not the bare exe.
      expect(fetcher.requestedUrls.single, contains('TaskPin-windows.zip'));
      expect(fetcher.requestedUrls.single, isNot(contains('taskpin-x64.exe')));

      // It extracted with a tool Windows ships.
      expect(runner.ran, isNotEmpty);
      expect(runner.ran.first.first, 'tar');

      // The batch copies the whole tree, restarts, and self-deletes.
      final String bat = File(
        '${root.path}${Platform.pathSeparator}tmp'
        '${Platform.pathSeparator}taskpin_update.bat',
      ).readAsStringSync();
      expect(bat, contains('xcopy /e /y /i'));
      expect(bat, contains('start "'));
      expect(bat, contains('rmdir /s /q'));
      expect(bat, contains('del "%~f0"'));

      // It launched the batch detached and exited.
      expect(runner.started.single.first, 'cmd');
      expect(exitHook.codes, <int>[0]);
      expect(s.applied, isTrue);
    });

    test('a download failure opens the release page and does not exit', () async {
      fetcher.onFailure('/TaskPin-windows.zip');
      final UpdateService s = service(modern: true);

      final UpdateApplyResult result = await s.apply(available);

      expect(result.status, UpdateApplyStatus.downloadFailed);
      expect(opener.opened.single, contains('TaskPin-windows.zip'));
      expect(exitHook.codes, isEmpty);
      expect(runner.started, isEmpty);
    });

    test('falls back to PowerShell when tar fails', () async {
      fetcher.onBytes('/TaskPin-windows.zip', <int>[80, 75, 3, 4]);
      runner.runExitCode = 1; // tar fails
      final UpdateService s = service(modern: true);

      await s.apply(available);

      // tar was tried, then powershell.
      expect(runner.ran.map((List<String> c) => c.first).toList(),
          <String>['tar', 'powershell']);
    });
  });

  group('the legacy (single-exe) apply', () {
    test('downloads the bare exe and writes the C-template batch', () async {
      fetcher.onBytes('/taskpin-x64.exe', <int>[77, 90]);
      final UpdateService s = service(modern: false);

      final UpdateApplyResult result = await s.apply(available);

      expect(result.status, UpdateApplyStatus.restarting);
      expect(fetcher.requestedUrls.single, contains('taskpin-x64.exe'));
      expect(fetcher.requestedUrls.single, isNot(contains('.zip')));

      final String bat = File(
        '${root.path}${Platform.pathSeparator}tmp'
        '${Platform.pathSeparator}taskpin_update.bat',
      ).readAsStringSync();
      // The single-file `copy /y`, NOT the tree `xcopy`.
      expect(bat, contains('copy /y'));
      expect(bat, isNot(contains('xcopy')));
      expect(exitHook.codes, <int>[0]);
    });
  });

  group('batch templates', () {
    test('the legacy builder is character-for-character the C template', () {
      // `lib/update.c:98-105`. The four `%s` are (tmpExe, curExe, curExe, tmpExe)
      // and `%%` is a literal `%`.
      final String built = UpdateService.buildUpdateBatch(
        currentExe: 'CUR',
        tmpExe: 'TMPEXE',
        tmpBat: 'TMPBAT',
      );
      expect(
        built,
        _substituteC(UpdateService.cBatchTemplate, <String>[
          'TMPEXE',
          'CUR',
          'CUR',
          'TMPEXE',
        ]),
      );
    });

    test('the zip builder copies the tree, restarts, and cleans up', () {
      final String bat = UpdateService.buildZipUpdateBatch(
        currentExe: r'C:\App\taskpin.exe',
        installDir: r'C:\App',
        stageDir: r'C:\Temp\stage',
        tmpZip: r'C:\Temp\taskpin_update.zip',
        tmpBat: r'C:\Temp\taskpin_update.bat',
      );
      expect(bat, startsWith('@echo off\r\n'));
      expect(bat, contains('timeout /t 2 /nobreak >nul\r\n'));
      expect(bat, contains(r'xcopy /e /y /i "C:\Temp\stage" "C:\App"'));
      expect(bat, contains(r'start "" "C:\App\taskpin.exe"'));
      expect(bat, contains(r'rmdir /s /q "C:\Temp\stage"'));
      expect(bat, contains(r'del "C:\Temp\taskpin_update.zip"'));
      expect(bat, endsWith('del "%~f0"\r\n'));
    });
  });
}

/// Substitutes the four `%s` in the C template positionally, leaving `%%` alone.
String _substituteC(String template, List<String> args) {
  final StringBuffer out = StringBuffer();
  int arg = 0;
  for (int i = 0; i < template.length; i++) {
    if (template[i] == '%' && i + 1 < template.length) {
      if (template[i + 1] == 's') {
        out.write(args[arg++]);
        i++;
        continue;
      }
      if (template[i + 1] == '%') {
        out.write('%');
        i++;
        continue;
      }
    }
    out.write(template[i]);
  }
  return out.toString();
}
