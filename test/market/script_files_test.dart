// Install state: one helper for the market and the project list.
//
// The two pages used to disagree. The market matched an item by file name
// only; the project list resolved `lua_path` on disk. An item pointing at a
// file that had been moved therefore read 已安装 in the market and 找不到脚本文件
// in the project list. These tests pin the shared rule.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/scripts/script_files.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('taskpin_script_files_test');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on Object {
      // Best effort.
    }
  });

  PinItem lua(String path) =>
      PinItem(type: PinItemType.lua, name: 'x', luaPath: path);

  File write(String name) {
    final File f = File('${tmp.path}${Platform.pathSeparator}$name');
    f.writeAsStringSync('return 1');
    return f;
  }

  test('an item whose file is missing is not installed', () {
    final TaskPinConfig config = TaskPinConfig(
      items: <PinItem>[lua('${tmp.path}\\gone.lua')],
    );
    expect(itemIndexForScript(config, 'gone.lua', baseDir: tmp.path), -1);
    expect(
      scriptInstallState(
        config: config,
        baseDir: tmp.path,
        scriptsDir: '${tmp.path}\\scripts',
        file: 'gone.lua',
      ).installed,
      isFalse,
    );
  });

  test('an item whose file resolves is installed', () {
    final File file = write('there.lua');
    final TaskPinConfig config = TaskPinConfig(items: <PinItem>[lua(file.path)]);
    expect(itemIndexForScript(config, 'there.lua', baseDir: tmp.path), 0);
  });

  test('a relative lua_path resolves against baseDir, like the runtime', () {
    final Directory scripts = Directory('${tmp.path}\\scripts')
      ..createSync();
    File('${scripts.path}\\relative.lua').writeAsStringSync('return 1');
    final TaskPinConfig config = TaskPinConfig(
      items: <PinItem>[lua('scripts\\relative.lua')],
    );
    expect(itemIndexForScript(config, 'relative.lua', baseDir: tmp.path), 0);
  });

  test('the file in scriptsDir counts even with no item', () {
    final String scriptsDir = '${tmp.path}\\scripts';
    Directory(scriptsDir).createSync();
    File('$scriptsDir\\orphan.lua').writeAsStringSync('return 1');

    final ScriptInstallState state = scriptInstallState(
      config: TaskPinConfig(),
      baseDir: tmp.path,
      scriptsDir: scriptsDir,
      file: 'orphan.lua',
    );
    expect(state.itemIndex, -1);
    expect(state.onDisk, isTrue);
    expect(state.installed, isTrue);
  });

  test('an item with the right name but a stale path is not installed', () {
    // The regression: the market used to match the basename alone.
    final TaskPinConfig config = TaskPinConfig(
      items: <PinItem>[lua('${tmp.path}\\moved-away\\trending.lua')],
    );
    expect(itemIndexForScript(config, 'trending.lua', baseDir: tmp.path), -1);
  });
}
