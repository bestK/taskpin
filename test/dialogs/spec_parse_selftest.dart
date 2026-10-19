// Standalone parser selftest — runs under a bare Dart VM.
//
//   dart run test/dialogs/spec_parse_selftest.dart
//
// Why this exists alongside `spec_parse_test.dart`: the golden files are real
// `engine_cli.exe` output, and this harness verifies the Dart parser against
// them with no Flutter SDK, no `pub get`, no package resolution and no test
// runner. On a box where `flutter_tools.snapshot` cannot be built that is the
// difference between "verified" and "asserted". It imports the model by
// relative path, which is legal because it is `dart run`, not a package test.
//
// Exits non-zero on the first failure. Output is plain text so it can be pasted
// into a report verbatim.

import 'dart:convert';
import 'dart:io';

import '../../lib/features/dialogs/dialog_spec.dart';

int _pass = 0;
int _fail = 0;

void check(String name, Object? expected, Object? actual) {
  if ('$expected' == '$actual') {
    _pass++;
    stdout.writeln('  PASS  $name');
  } else {
    _fail++;
    stdout.writeln('  FAIL  $name');
    stdout.writeln('        expected: $expected');
    stdout.writeln('        actual:   $actual');
  }
}

Map<String, dynamic> load(String name) {
  final File f = File('test/dialogs/golden/$name.json');
  if (!f.existsSync()) {
    throw StateError('missing golden ${f.path} — regenerate with engine_cli');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  stdout.writeln(
    '== golden: hud_clock (borderless + clickthrough + opacity 180) ==',
  );
  {
    final Map<String, dynamic> r = load('hud_clock');
    final DialogSpec? spec = DialogSpec.fromScriptResult(r);
    check('spec is present', true, spec != null);
    final DialogSpec s = spec!;
    check('title', 'Clock', s.title);
    check('size from script', '200x80', '${s.width}x${s.height}');
    check('refresh seconds', 1, s.refreshSeconds);
    check('borderless', true, s.borderless);
    check('clickthrough', true, s.clickthrough);
    check('opacity', 180, s.opacity);
    check('needs layered (clickthrough||opacity<255)', true, s.needsLayered);
    check('item count', 2, s.items.length);
    check('item0 kind', TpDialogItemKind.text, s.items[0].kind);
    check('item0 color', '#FFFFFF', s.items[0].color);
    check('item0 size', 24, s.items[0].fontSize);
    check('item0 bold', true, s.items[0].bold);
    check('item1 color', '#AAAAAA', s.items[1].color);
    check('item1 not bold', false, s.items[1].bold);
    // Round-trip: the parsed spec must re-emit the engine's own key names.
    final Map<String, dynamic> back = s.toJson();
    check('round-trip title', r['dialog']['title'], back['title']);
    check('round-trip opacity', r['dialog']['opacity'], back['opacity']);
    check(
      'round-trip item_count',
      r['dialog']['item_count'],
      back['item_count'],
    );
    check(
      'round-trip item0 value',
      r['dialog']['items'][0]['value'],
      back['items'][0]['value'],
    );
    check('round-trip rows (empty)', '[]', '${back['items'][0]['rows']}');
  }

  stdout.writeln(
    '== golden: all_items (every item type, buttons + row actions) ==',
  );
  {
    final Map<String, dynamic> r = load('all_items');
    final DialogSpec s = DialogSpec.fromScriptResult(r)!;
    check('item count', 8, s.items.length);
    check(
      'kinds in order',
      '[text, text, text, hr, table, image, button, button]',
      s.items
          .map((DialogItem i) => i.kind.name)
          .toList()
          .toString()
          .replaceAll('TpDialogItemKind.', ''),
    );

    final DialogItem table = s.items[4];
    check('table columns', '[Name, State]', table.columns);
    check('table colCount', 2, table.colCount);
    check('table rowCount', 3, table.rowCount);
    check('table cell[1][1]', 'down', table.cells[1][1]);
    check('row0 has no action', false, table.rowHasAction(0));
    check('row1 has url', 'https://example.com/beta', table.rowUrls[1]);
    check('row2 has cmd', 'echo gamma', table.rowCmds[2]);
    check('hasAnyRowAction', true, table.hasAnyRowAction);
    check('empty row_urls padded to rowCount', 3, table.rowUrls.length);

    final DialogItem img = s.items[5];
    check('image source', 'https://example.com/pic.png', img.image);
    check('image size', '48x48', '${img.imageWidth}x${img.imageHeight}');

    final DialogItem btnUrl = s.items[6];
    check('button label', 'Open site', btnUrl.value);
    check('button url', 'https://example.com/', btnUrl.url);
    check('button bg', '#333333', btnUrl.bg);
    check('button fg', '#4FC3F7', btnUrl.color);
    check('button actionable', true, btnUrl.isActionable);

    final DialogItem btnCmd = s.items[7];
    check('cmd button has no url', '', btnCmd.url);
    check('cmd button cmd', 'echo hello', btnCmd.cmd);
    check('cmd button actionable', true, btnCmd.isActionable);

    // Short-hex colour `#ABC` must survive verbatim: it is the wire string the
    // engine sent, and `parse_color_str` (lib/scripting.c:154-156) expands it
    // to `#AABBCC` only at render time.
    check('short hex preserved', '#ABC', s.items[1].color);

    final Map<String, dynamic> back = s.toJson();
    check(
      'round-trip columns',
      r['dialog']['items'][4]['columns'],
      back['items'][4]['columns'],
    );
    check(
      'round-trip row_urls',
      r['dialog']['items'][4]['row_urls'],
      back['items'][4]['row_urls'],
    );
    check(
      'round-trip web_w',
      r['dialog']['items'][4]['web_w'],
      back['items'][4]['web_w'],
    );
    check(
      'round-trip image_width',
      r['dialog']['items'][5]['image_width'],
      back['items'][5]['image_width'],
    );
  }

  stdout.writeln('== golden: webview_demo (transparent_bg + webview type) ==');
  {
    final Map<String, dynamic> r = load('webview_demo');
    final DialogSpec s = DialogSpec.fromScriptResult(r)!;
    check('transparent_bg', true, s.transparentBg);
    check('borderless', true, s.borderless);
    check('clickthrough false', false, s.clickthrough);
    check('opacity 255 -> no layered', false, s.needsLayered);
    check('item kind', TpDialogItemKind.webview, s.items[0].kind);
    check(
      'web url',
      true,
      s.items[0].url.startsWith('https://raw.githubusercontent'),
    );
    check(
      'web box',
      '580x460',
      '${s.items[0].webWidth}x${s.items[0].webHeight}',
    );
  }

  stdout.writeln(
    '== golden: image_dialog_demo (inline icons + standalone image) ==',
  );
  {
    final DialogSpec s = DialogSpec.fromScriptResult(
      load('image_dialog_demo'),
    )!;
    check('item count', 6, s.items.length);
    check('inline icon on text', true, s.items[0].image.isNotEmpty);
    check(
      'inline icon box',
      '20x20',
      '${s.items[0].imageWidth}x${s.items[0].imageHeight}',
    );
    check('standalone image kind', TpDialogItemKind.image, s.items[4].kind);
    check(
      'standalone image box',
      '64x64',
      '${s.items[4].imageWidth}x${s.items[4].imageHeight}',
    );
    check('hr in the middle', TpDialogItemKind.hr, s.items[1].kind);
  }

  stdout.writeln('== golden: net_monitor (4 cols x 15 rows) ==');
  {
    final DialogSpec s = DialogSpec.fromScriptResult(load('net_monitor'))!;
    check('item count', 3, s.items.length);
    final DialogItem t = s.items[2];
    check('table kind', TpDialogItemKind.table, t.kind);
    check('colCount', 4, t.colCount);
    check('columns', '[Process, Conn, Download, Upload]', t.columns);
    check('rowCount', 15, t.rowCount);
    check('no row actions in this script', false, t.hasAnyRowAction);
  }

  stdout.writeln(
    '== golden: rich_text_demo (span-only; must NOT open a dialog) ==',
  );
  {
    final Map<String, dynamic> r = load('rich_text_demo');
    check('click_action is url', 0, r['click_action']);
    check(
      'no dialog from a span-only result',
      null,
      DialogSpec.fromScriptResult(r),
    );
    check('spans still parsed by the bar model, not here', 7, r['span_count']);
  }

  stdout.writeln('== limits: 8 items / 6 cols / 24 rows ==');
  {
    final Map<String, dynamic> big = <String, dynamic>{
      'title': 'Big',
      'width': 0,
      'height': 0,
      'refresh': 0,
      'borderless': 0,
      'clickthrough': 0,
      'opacity': 300,
      'bg_color': '',
      'transparent_bg': 0,
      'item_count': 12,
      'items': List<Map<String, dynamic>>.generate(
        12,
        (int i) => <String, dynamic>{'type': 'text', 'value': 'i$i'},
      ),
    };
    final DialogSpec s = DialogSpec.fromJson(big);
    check('items clamped to 8', 8, s.items.length);
    check('width 0 -> 400 default', 400, s.width);
    check('height 0 -> 300 default', 300, s.height);
    check('opacity clamped to 255', 255, s.opacity);

    final DialogItem wide = DialogItem.fromJson(<String, dynamic>{
      'type': 'table',
      'columns': List<String>.generate(9, (int i) => 'c$i'),
      'rows': List<List<String>>.generate(
        30,
        (int i) => List<String>.generate(9, (int j) => 'r$i$j'),
      ),
      'row_urls': List<String>.generate(30, (int i) => 'u$i'),
      'row_cmds': List<String>.generate(30, (int i) => 'k$i'),
    });
    check('cols clamped to 6', 6, wide.colCount);
    check('rows clamped to 24', 24, wide.rowCount);
    check('each row clamped to colCount', 6, wide.cells[0].length);
    check('row_urls clamped to 24', 24, wide.rowUrls.length);
    check('row_urls survives at index 23', 'u23', wide.rowUrls[23]);
    check('truncated column values kept', 'r00', wide.cells[0][0]);
  }

  stdout.writeln('== degenerate input: never throws ==');
  {
    final DialogSpec s = DialogSpec.fromJson(const <String, dynamic>{});
    check(
      'empty map -> defaults',
      'Dialog/400x300/0',
      '${s.title}/${s.width}x${s.height}/${s.items.length}',
    );
    check('empty map -> opacity 255', 255, s.opacity);

    check(
      'unknown type -> unknown kind',
      TpDialogItemKind.unknown,
      DialogItem.fromJson(const <String, dynamic>{'type': 'marquee'}).kind,
    );
    check(
      'missing type -> unknown kind',
      TpDialogItemKind.unknown,
      DialogItem.fromJson(const <String, dynamic>{}).kind,
    );
    check(
      'rawType kept for diagnostics',
      'marquee',
      DialogItem.fromJson(const <String, dynamic>{'type': 'marquee'}).rawType,
    );

    // A negative opacity is clamped rather than wrapping (the C layer clamps
    // the same way, lib/scripting.c:541-542).
    check(
      'negative opacity -> 0',
      0,
      DialogSpec.fromJson(const <String, dynamic>{'opacity': -5}).opacity,
    );

    // Non-list `items` / `rows` / `columns` are tolerated.
    final DialogItem junk = DialogItem.fromJson(const <String, dynamic>{
      'type': 'table',
      'columns': 'not-a-list',
      'rows': 42,
      'row_urls': null,
    });
    check('non-list columns -> empty', 0, junk.colCount);
    check('non-list rows -> empty', 0, junk.rowCount);

    // click_action == CLICK_URL must not yield a dialog even with items present.
    final Map<String, dynamic> asUrl = Map<String, dynamic>.from(
      load('hud_clock'),
    );
    asUrl['click_action'] = 0;
    check(
      'click_action=url -> no dialog',
      null,
      DialogSpec.fromScriptResult(asUrl),
    );
    final Map<String, dynamic> notClickable = Map<String, dynamic>.from(
      load('hud_clock'),
    );
    notClickable['clickable'] = 0;
    check(
      'clickable=0 -> no dialog',
      null,
      DialogSpec.fromScriptResult(notClickable),
    );
    // ...and an empty item list is not a dialog either.
    final Map<String, dynamic> noItems = Map<String, dynamic>.from(
      load('hud_clock'),
    );
    noItems['dialog'] = <String, dynamic>{'title': 'x', 'items': <dynamic>[]};
    check('0 items -> no dialog', null, DialogSpec.fromScriptResult(noItems));
  }

  stdout.writeln('');
  stdout.writeln('$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
