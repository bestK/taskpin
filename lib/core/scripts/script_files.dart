// Where a script lives on disk, and whether it is installed.
//
// The market and the project list must agree on "installed". They used to
// disagree: the market called a plugin installed when any item referenced its
// file NAME, while the project list resolved the item's `lua_path` and reported
// 找不到脚本文件 when that path did not exist. Both now ask this file.
//
// Resolution is the runtime's: a relative `lua_path` is resolved against
// `ConfigPaths.baseDir`, exactly as `resolveScriptPath` does when the engine
// runs the script.

import 'dart:io';

import '../bar/bar_source.dart' show resolveScriptPath;
import '../config/config_schema.dart';

/// The final path component of a Windows or POSIX path.
String scriptBasename(String path) {
  final int slash = path.lastIndexOf('/');
  final int backslash = path.lastIndexOf('\\');
  final int cut = slash > backslash ? slash : backslash;
  return cut >= 0 ? path.substring(cut + 1) : path;
}

/// Whether [path] resolves to an existing file.
///
/// [baseDir] is `ConfigPaths.baseDir`. A malformed path is treated as missing
/// rather than throwing.
bool scriptFileExists(String path, String baseDir) {
  try {
    return File(resolveScriptPath(path, baseDir)).existsSync();
  } on Object {
    return false;
  }
}

/// Where [file] is installed in [scriptsDir].
String scriptPathIn(String scriptsDir, String file) {
  if (scriptsDir.isEmpty) return file;
  final String sep = Platform.pathSeparator;
  final String base = scriptsDir.endsWith(sep) || scriptsDir.endsWith('/')
      ? scriptsDir
      : '$scriptsDir$sep';
  return '$base$file';
}

/// Index of the Lua item that references [file] AND resolves on disk, or -1.
///
/// Matching is by file name, case-insensitively, so the same script installed
/// to a different directory still matches. An item whose path is stale does
/// not count: the project list reports that item as missing, and the market
/// must not call it installed.
int itemIndexForScript(
  TaskPinConfig config,
  String file, {
  required String baseDir,
}) {
  final String want = scriptBasename(file).toLowerCase();
  for (int i = 0; i < config.items.length; i++) {
    final PinItem item = config.items[i];
    if (item.type != PinItemType.lua) continue;
    if (scriptBasename(item.luaPath).toLowerCase() != want) continue;
    if (scriptFileExists(item.luaPath, baseDir)) return i;
  }
  return -1;
}

/// What is known about one market script on this machine.
class ScriptInstallState {
  const ScriptInstallState({this.itemIndex = -1, this.onDisk = false});

  /// The item that references the script and resolves, or -1.
  final int itemIndex;

  /// The file exists in the configured scripts directory.
  final bool onDisk;

  /// Installed when either half is true.
  bool get installed => itemIndex >= 0 || onDisk;
}

/// Resolve the install state of [file].
ScriptInstallState scriptInstallState({
  required TaskPinConfig config,
  required String baseDir,
  required String scriptsDir,
  required String file,
}) {
  return ScriptInstallState(
    itemIndex: itemIndexForScript(config, file, baseDir: baseDir),
    onDisk: scriptFileExists(scriptPathIn(scriptsDir, file), baseDir),
  );
}
