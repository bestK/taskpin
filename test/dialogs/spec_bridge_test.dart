// Engine spec -> UI spec.
//
// The bar click path hands the dialog window a `ScriptResult.dialog`, which is
// the ENGINE's `DialogSpec`. The window renders the UI's `DialogSpec`. Nothing
// bridged the two, so `dialogOpenerProvider` was never wired and a click on a
// bar whose script returned `dialog(...)` did nothing at all.
//
// These tests pin the bridge: every field the engine carries must survive, and
// the table's body rows must arrive under the key the UI parser reads (`rows`,
// not `cells` — that mistake already cost one test in the dialog render suite).

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart' as ui;
import 'package:taskpin/features/dialogs/dialog_spec_bridge.dart';
import 'package:taskpin_engine/taskpin_engine.dart' as engine;

engine.DialogItem _item({
  engine.DialogItemType type = engine.DialogItemType.text,
  String value = '',
  String color = '',
  int fontSize = 0,
  bool bold = false,
  String url = '',
  String cmd = '',
  List<String> columns = const <String>[],
  List<List<String>> rows = const <List<String>>[],
  List<String> rowUrls = const <String>[],
  List<String> rowCmds = const <String>[],
}) =>
    engine.DialogItem(
      type: type,
      value: value,
      color: color,
      fontSize: fontSize,
      bold: bold,
      image: '',
      imageWidth: 0,
      imageHeight: 0,
      url: url,
      cmd: cmd,
      bg: '',
      webWidth: 0,
      webHeight: 0,
      columns: columns,
      rows: rows,
      rowUrls: rowUrls,
      rowCmds: rowCmds,
    );

engine.DialogSpec _spec(List<engine.DialogItem> items) => engine.DialogSpec(
      title: 'Status',
      width: 420,
      height: 300,
      refresh: 5,
      borderless: true,
      clickthrough: false,
      opacity: 200,
      backgroundColor: '#101010',
      transparentBackground: false,
      items: items,
    );

void main() {
  test('an empty payload yields no window', () {
    expect(uiSpecFromEngine(_spec(<engine.DialogItem>[])), isNull);
  });

  test('dialog-level fields survive the conversion', () {
    final ui.DialogSpec? spec =
        uiSpecFromEngine(_spec(<engine.DialogItem>[_item(value: 'hello')]));
    expect(spec, isNotNull);
    expect(spec!.title, 'Status');
    expect(spec.width, 420);
    expect(spec.height, 300);
    expect(spec.refreshSeconds, 5);
    expect(spec.borderless, isTrue);
    expect(spec.clickthrough, isFalse);
    expect(spec.opacity, 200);
    expect(spec.bgColor, '#101010');
  });

  test('a text item keeps its value, colour and weight', () {
    final ui.DialogSpec spec = uiSpecFromEngine(
      _spec(<engine.DialogItem>[
        _item(value: 'CPU 42%', color: '#FF8800', fontSize: 13, bold: true),
      ]),
    )!;
    final ui.DialogItem item = spec.items.single;
    expect(item.kind, ui.TpDialogItemKind.text);
    expect(item.value, 'CPU 42%');
    expect(item.color, '#FF8800');
    expect(item.fontSize, 13);
    expect(item.bold, isTrue);
  });

  test('a table keeps its columns and every body row', () {
    final ui.DialogSpec spec = uiSpecFromEngine(
      _spec(<engine.DialogItem>[
        _item(
          type: engine.DialogItemType.table,
          columns: <String>['A', 'B'],
          rows: <List<String>>[
            <String>['1', '2'],
            <String>['3', '4'],
          ],
        ),
      ]),
    )!;
    final ui.DialogItem table = spec.items.single;
    expect(table.kind, ui.TpDialogItemKind.table);
    expect(table.columns, <String>['A', 'B']);
    expect(table.rowCount, 2, reason: 'body rows must arrive under "rows"');
    expect(table.cells, <List<String>>[
      <String>['1', '2'],
      <String>['3', '4'],
    ]);
  });

  test('a button keeps its url and command', () {
    final ui.DialogSpec spec = uiSpecFromEngine(
      _spec(<engine.DialogItem>[
        _item(type: engine.DialogItemType.button, value: 'Open', url: 'https://x', cmd: 'calc'),
      ]),
    )!;
    final ui.DialogItem button = spec.items.single;
    expect(button.kind, ui.TpDialogItemKind.button);
    expect(button.value, 'Open');
    expect(button.url, 'https://x');
    expect(button.cmd, 'calc');
  });

  test('per-row actions survive', () {
    final ui.DialogSpec spec = uiSpecFromEngine(
      _spec(<engine.DialogItem>[
        _item(
          type: engine.DialogItemType.table,
          columns: <String>['A'],
          rows: <List<String>>[
            <String>['x'],
          ],
          rowUrls: <String>['https://a'],
          rowCmds: <String>[''],
        ),
      ]),
    )!;
    final ui.DialogItem table = spec.items.single;
    expect(table.rowHasAction(0), isTrue);
    expect(table.rowUrls.single, 'https://a');
  });
}
