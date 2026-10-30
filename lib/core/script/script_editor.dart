// Opening a project's Lua script for reading or editing.
//
// Two ways, because they answer different questions:
//
//   * the DEFAULT app — whatever Windows associates with `.lua`, or the
//     fallback `explorer.exe` uses. One click, no setup, and the right answer
//     for someone who only wants to look.
//   * a DETECTED editor — VS Code, Cursor, Notepad++, Sublime, Notepad. The
//     app cannot ask Windows "which editors are installed", so this probes the
//     places these editors put themselves: the standard per-user and
//     per-machine install directories, and PATH.
//
// Detection is done once and cached (see [scriptEditorsProvider]); it touches
// the disk, so it must not run on every rebuild.

import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One editor this machine can open a script with.
@immutable
class ScriptEditor {
  const ScriptEditor({required this.label, required this.executable});

  /// What the menu says, e.g. `VS Code`.
  final String label;

  /// Full path to the executable.
  final String executable;

  @override
  bool operator ==(Object other) =>
      other is ScriptEditor &&
      other.label == label &&
      other.executable == executable;

  @override
  int get hashCode => Object.hash(label, executable);
}

/// Editors found on this machine, best-known first.
///
/// [environment] is injectable so a test can describe a machine instead of
/// depending on the one running it.
Future<List<ScriptEditor>> detectScriptEditors({
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) async {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return const <ScriptEditor>[];
  }
  final Map<String, String> env = environment ?? Platform.environment;
  final bool Function(String) has =
      exists ?? (String path) => File(path).existsSync();

  final List<ScriptEditor> found = <ScriptEditor>[];
  void add(String label, List<String> candidates) {
    for (final String candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (has(candidate)) {
        found.add(ScriptEditor(label: label, executable: candidate));
        return;
      }
    }
  }

  if (Platform.isWindows) {
    final String local = env['LOCALAPPDATA'] ?? '';
    final String programFiles = env['ProgramFiles'] ?? '';
    final String programFilesX86 = env['ProgramFiles(x86)'] ?? '';
    final String systemRoot = env['SystemRoot'] ?? r'C:\Windows';

    add('VS Code', <String>[
      if (local.isNotEmpty)
        '$local\\Programs\\Microsoft VS Code\\Code.exe',
      if (programFiles.isNotEmpty)
        '$programFiles\\Microsoft VS Code\\Code.exe',
    ]);
    add('Cursor', <String>[
      if (local.isNotEmpty) '$local\\Programs\\cursor\\Cursor.exe',
      if (programFiles.isNotEmpty) '$programFiles\\Cursor\\Cursor.exe',
    ]);
    add('Notepad++', <String>[
      if (programFiles.isNotEmpty) '$programFiles\\Notepad++\\notepad++.exe',
      if (programFilesX86.isNotEmpty)
        '$programFilesX86\\Notepad++\\notepad++.exe',
    ]);
    add('Sublime Text', <String>[
      if (programFiles.isNotEmpty)
        '$programFiles\\Sublime Text\\sublime_text.exe',
      if (programFiles.isNotEmpty)
        '$programFiles\\Sublime Text 3\\sublime_text.exe',
    ]);
    // Always present on Windows, and the honest last resort when nothing else
    // is installed: a script you can read is better than a menu that is empty.
    add('记事本', <String>['$systemRoot\\System32\\notepad.exe']);
  } else if (Platform.isMacOS) {
    add('TextEdit', <String>['/System/Applications/TextEdit.app']);
  }
  return found;
}

/// Open [path] with whatever the OS associates with it.
///
/// `explorer.exe` is used on Windows rather than `cmd /c start`: it is the
/// shell itself, so the default association applies and no console window
/// flashes.
Future<bool> openPathWithDefaultApp(String path) async {
  if (path.trim().isEmpty) return false;
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>[path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', <String>[path]);
    } else {
      await Process.run('xdg-open', <String>[path]);
    }
    return true;
  } on Object {
    return false;
  }
}

/// Open [path] in [editor].
Future<bool> openPathWithEditor(ScriptEditor editor, String path) async {
  if (path.trim().isEmpty) return false;
  try {
    await Process.start(
      editor.executable,
      <String>[path],
      mode: ProcessStartMode.detached,
    );
    return true;
  } on Object {
    return false;
  }
}

/// The editors found on this machine, detected once per session.
final FutureProvider<List<ScriptEditor>> scriptEditorsProvider =
    FutureProvider<List<ScriptEditor>>((Ref ref) => detectScriptEditors());
