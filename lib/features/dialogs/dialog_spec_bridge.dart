// Engine spec -> UI spec.
//
// There are TWO `DialogSpec` types in this codebase, and they are not the same
// class:
//
//   `package:taskpin_engine`      the engine's output: an immutable value read
//                                 out of the C ABI's POD structs, with
//                                 `DialogItemType` as an enum.
//
//   `features/dialogs/dialog_spec` the UI's model: wire strings kept as
//                                 strings, clamping applied, and the parsing
//                                 entry points the dialog window and the golden
//                                 tests use.
//
// The bar click path produces the first (it comes from `ScriptResult.dialog`)
// and `DialogWindowHost.open` wants the second. Neither file may import the
// other: the UI model is deliberately package-free so it runs under a bare
// `dart` VM, and the engine model knows nothing about UI concerns. This file is
// the one place that bridges them, and it lives in the app layer because that
// is the only layer allowed to know both.
//
// The conversion goes through the engine's wire vocabulary (`'text'`, `'hr'`,
// ...), which is the same vocabulary the UI model already parses from
// `TPScriptResult` JSON. That keeps a single parser in charge of validation
// (clamping row/column counts, dropping unknown item kinds) instead of adding a
// second, subtly different one here.

import 'package:taskpin_engine/taskpin_engine.dart' as engine;

import 'dialog_spec.dart' as ui;

/// Convert the engine's dialog payload into the UI model.
///
/// Returns null when the payload carries no items — the same gate
/// `DialogSpec.fromScriptResult` applies before anything is shown
/// (`lib/script_dialog.c:362`).
ui.DialogSpec? uiSpecFromEngine(engine.DialogSpec spec) {
  if (spec.items.isEmpty) {
    return null;
  }
  return ui.DialogSpec.fromJson(<String, dynamic>{
    'title': spec.title,
    'width': spec.width,
    'height': spec.height,
    'refresh': spec.refresh,
    'borderless': spec.borderless ? 1 : 0,
    'clickthrough': spec.clickthrough ? 1 : 0,
    'opacity': spec.opacity,
    'bg_color': spec.backgroundColor,
    'transparent_bg': spec.transparentBackground ? 1 : 0,
    'items': <Map<String, dynamic>>[
      for (final engine.DialogItem item in spec.items) _itemToJson(item),
    ],
  });
}

Map<String, dynamic> _itemToJson(engine.DialogItem item) => <String, dynamic>{
  // `wireValue` is the engine's own spelling (`'text'`, `'hr'`, ...), which is
  // exactly what the UI parser switches on.
  'type': item.type.wireValue,
  'value': item.value,
  'color': item.color,
  'font_size': item.fontSize,
  'bold': item.bold ? 1 : 0,
  'image': item.image,
  'image_width': item.imageWidth,
  'image_height': item.imageHeight,
  'url': item.url,
  'cmd': item.cmd,
  'bg': item.bg,
  'web_w': item.webWidth,
  'web_h': item.webHeight,
  'columns': item.columns,
  // The UI parser's key for body rows is `rows` (it matches `TPDialogItem` and
  // `DialogItem.toJson`), NOT `cells`, which is the Dart field name.
  'rows': item.rows,
  'row_urls': item.rowUrls,
  'row_cmds': item.rowCmds,
};
