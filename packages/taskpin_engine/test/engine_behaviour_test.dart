/// Engine behaviour: run real Lua scripts through the C engine, from Dart.
///
/// The engine under test is the shipped one — `native/engine`, the same sources
/// linked statically into the Windows runner. It is loaded from a DLL only
/// because `dart test` has no runner to link against (see the package README).
///
/// Goldens: `examples/` and `scripts/` ship several scripts, but most are NOT
/// deterministic on purpose:
///
///   * `rich_text_demo.lua` and `hud_clock.lua` embed `os.date()` output;
///   * `system_monitor.lua` embeds live CPU/memory/network readings;
///   * `zeeho.lua` performs a real HTTP request whose branch varies.
///
/// Asserting those exactly would make this suite flaky for no benefit, so it is
/// split into three tiers:
///
///   1. EXACT     — deterministic fixtures written for this test.
///   2. NORMALIZED — structural fields compared exactly; only the volatile
///                   substrings (timestamps, numbers) normalised away.
///   3. CONTRACT  — shape and types only, for `zeeho`.
///
/// `dino_runner.lua` and `webview_demo.lua` are here too, because they exercise
/// APIs that were missing entirely until this rewrite
/// (`sys.watch_keys`/`sys.key_pressed`/`sys.key_triggered`, the `webview` dialog
/// item, `sys.is_china`/`sys.gh_proxy`). Both used to return `ok: 0` with
/// "attempt to call a nil value".

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:taskpin_engine/taskpin_engine.dart';
import 'package:test/test.dart';

/// Absolute path to a file in the repo, resolving from whichever directory
/// `dart test` was invoked in.
String repoFile(String relative) {
  final Directory here = Directory.current.absolute;
  // Two invocation shapes, and they differ in where the repo root is:
  //   * `cd packages/taskpin_engine && dart test`  -> cwd IS the package, so
  //     the repo root is two levels up;
  //   * `dart test packages/taskpin_engine` from the repo root -> cwd already
  //     IS the repo root.
  // Checking both is what makes `scripts/zeeho.lua` and `examples/...` resolve
  // either way. Ordering matters only for speed.
  final List<String> candidates = <String>[
    p.join(here.path, relative),
    p.join(here.path, '..', '..', relative),
  ];
  final String? found =
      candidates.where((String c) => File(c).existsSync()).firstOrNull;
  expect(
    found,
    isNotNull,
    reason: 'not found:\n  ${candidates.join('\n  ')}',
  );
  return found!;
}

void main() {
  group('engine basics', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('a font()-only script returns one text span', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/a.lua')
        ..writeAsStringSync('return font("hello", "#FF8800", 12)');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.error, isEmpty);
      expect(r.spans, hasLength(1));
      expect(r.spans.single.text, 'hello');
      expect(r.spans.single.color, '#FF8800');
      expect(r.spans.single.fontSize, 12);
      // Not an image, left-aligned, not a line break.
      expect(r.spans.single.isImage, isFalse);
      expect(r.spans.single.align, SpanAlign.left);
      expect(r.spans.single.newline, isFalse);
    });

    test('spans concatenate with .. and keep their own attributes', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/b.lua')
        ..writeAsStringSync('return font("A", "#111111") .. font("B", "#222222")');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans, hasLength(2));
      expect(r.spans[0].text, 'A');
      expect(r.spans[0].color, '#111111');
      expect(r.spans[1].text, 'B');
      expect(r.spans[1].color, '#222222');
    });

    test('a 2-arg font() keeps its colour', () async {
      // This is the macOS-only regression: the old bridge guarded with
      // `lua_gettop(L) >= 3`, so `font("a", "#fff")` silently dropped the
      // colour on macOS while working on Windows. The unified engine gets this
      // right for both.
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/c.lua')
        ..writeAsStringSync('return font("x", "#FF0000")');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans.single.color, '#FF0000');
      expect(r.spans.single.fontSize, 0,
          reason: 'no size given, so 0 = use the global default');
    });

    test('a newline span splits the two lines', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/d.lua')
        ..writeAsStringSync(
            'return font("line1", "#FFF", 9) .. font("\\n") .. font("line2", "#0F0", 9)');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans, hasLength(3));
      expect(r.spans[1].newline, isTrue);
      // The break is a FLAG, not a character: the engine sets `newline` and
      // leaves `text` empty. Confirmed against real engine output.
      expect(r.spans[1].text, '');
    });

    test('alignment is reported per span', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/e.lua')
        ..writeAsStringSync(
            'return font("left", "#FFF", 9) .. font("right", "#888", 9, "right")');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans[0].align, SpanAlign.left);
      expect(r.spans[1].align, SpanAlign.right);
    });

    test('a click URL is returned as clickable with clickAction url', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/f.lua')
        ..writeAsStringSync(
            'return "go", true, "https://example.com/docs"');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.clickable, isTrue);
      expect(r.clickAction, ClickAction.url);
      expect(r.clickUrl, 'https://example.com/docs');
    });

    test('a dialog spec is returned as clickAction dialog', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/g.lua')
        ..writeAsStringSync('''
local d = dialog({
  title = "Status", width = 320, height = 200, refresh = 5,
  content = {
    { type = "text", value = "Title", color = "#FF8800", size = 12, bold = true },
    { type = "hr" },
    { type = "table", columns = {"Name", "Value"},
      rows = {{"CPU", "45%"}, {"MEM", "72%"}} },
  },
})
return "Status", true, d
''');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      expect(r.clickable, isTrue);
      expect(r.clickAction, ClickAction.dialog);

      final DialogSpec spec = r.dialog!;
      expect(spec.title, 'Status');
      expect(spec.width, 320);
      expect(spec.height, 200);
      expect(spec.refresh, 5);
      expect(spec.items, hasLength(3));

      // text
      expect(spec.items[0].type, DialogItemType.text);
      expect(spec.items[0].value, 'Title');
      expect(spec.items[0].color, '#FF8800');
      expect(spec.items[0].fontSize, 12);
      expect(spec.items[0].bold, isTrue);

      // hr
      expect(spec.items[1].type, DialogItemType.hr);

      // table
      expect(spec.items[2].type, DialogItemType.table);
      expect(spec.items[2].columns, <String>['Name', 'Value']);
      expect(spec.items[2].rows, hasLength(2));
      expect(spec.items[2].rows[0], <String>['CPU', '45%']);
    });

    test('an image span is reported as isImage with its size', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/h.lua')
        ..writeAsStringSync('return icon("examples/logo.png", 20, 20)');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      final Span img = r.spans.single;
      expect(img.isImage, isTrue);
      expect(img.imageWidth, 20);
      expect(img.imageHeight, 20);
      // The source is carried on `text` for image spans, matching the ABI.
      expect(img.text, 'examples/logo.png');
    });
  });

  group('error handling', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('a syntax error is reported, not thrown', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/i.lua')
        ..writeAsStringSync('return font(');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isFalse);
      expect(r.error, isNotEmpty);
      // Crucially the bad output must not land in `display` — that is how the
      // old renderer came to paint a Lua stack trace into the taskbar.
      expect(r.display, isEmpty);
      expect(r.spans, isEmpty);
    });

    test('a runtime error is reported with ok false', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/j.lua')
        ..writeAsStringSync('error("boom")');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isFalse);
      expect(r.error, contains('boom'));
      expect(r.spans, isEmpty);
    });

    test('a missing file is reported, not thrown', () async {
      final ScriptResult r =
          await engine.executeFile('definitely/not/here.lua');
      expect(r.ok, isFalse);
      expect(r.error, isNotEmpty);
    });
  });

  group('the instruction watchdog', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('an infinite loop is aborted instead of hanging', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/k.lua')
        ..writeAsStringSync('while true do end');

      final Future<ScriptResult> pending =
          engine.executeFile(f.path, argsJson: null);
      final ScriptResult r = await pending
          .timeout(const Duration(seconds: 2), onTimeout: () {
        fail('the engine hung — the watchdog did not fire');
      });

      expect(r.ok, isFalse);
      expect(r.error, contains('watchdog'));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a tight-but-finite loop still completes', () async {
      // The watchdog must not abort a merely slow script.
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/l.lua')
        ..writeAsStringSync('''
local n = 0
for i = 1, 2000000 do n = n + i end
return font(tostring(n), "#FFF", 9)
''');
      final ScriptResult r = await engine.executeFile(f.path);
      expect(r.ok, isTrue, reason: r.error);
    });
  });

  group('@param and @refresh parsing', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('declarations are parsed in order with key, type and label', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/m.lua')
        ..writeAsStringSync('''
-- @param server string Server address
-- @param port number Port number
-- @param token string API Token

return font("x")
''');
      final List<ParamDecl> decls = await engine.parseParams(f.path);

      expect(decls, hasLength(3));
      expect(decls.map((ParamDecl d) => d.key), <String>['server', 'port', 'token']);
      expect(decls[0].type, 'string');
      expect(decls[0].label, 'Server address');
      expect(decls[1].type, 'number');
    });

    test('the scan stops at the first non-comment line', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/n.lua')
        ..writeAsStringSync('''
-- @param real string Real
local x = 1
-- @param fake string Never seen
''');
      final List<ParamDecl> decls = await engine.parseParams(f.path);
      expect(decls.map((ParamDecl d) => d.key), <String>['real']);
    });

    test('@refresh is parsed as milliseconds', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/o.lua')
        ..writeAsStringSync('-- @refresh 20000\nreturn font("x")');
      expect(await engine.parseRefresh(f.path), 20000);
    });

    test('no @refresh means 0', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/p.lua')
        ..writeAsStringSync('return font("x")');
      expect(await engine.parseRefresh(f.path), 0);
    });

    test('the shipped zeeho.lua parses its VIN param and 30s refresh', () async {
      final String path = repoFile('scripts/zeeho.lua');
      final List<ParamDecl> decls = await engine.parseParams(path);
      expect(decls, hasLength(1));
      expect(decls.single.key, 'VIN');
      expect(await engine.parseRefresh(path), 30000);
    });
  });

  group('args reach the script as a table', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('args JSON becomes the `args` global', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/q.lua')
        ..writeAsStringSync('return font(tostring(args.name) .. "/" .. '
            'tostring(args.port), "#FFF", 9)');
      final ScriptResult r = await engine.executeFile(
        f.path,
        argsJson: '{"name":"prod","port":"8080"}',
      );

      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans.single.text, 'prod/8080');
    });

    test('a missing key reads as nil, not an error', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/r.lua')
        ..writeAsStringSync('return font(tostring(args.nope), "#FFF", 9)');
      final ScriptResult r = await engine.executeFile(f.path, argsJson: '{}');
      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans.single.text, 'nil');
    });
  });

  group('json.decode', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('objects and arrays decode into Lua tables', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/s.lua')
        ..writeAsStringSync('''
local d = json.decode('{"user":{"name":"ada","tags":["a","b"]}}')
return font(d.user.name .. ":" .. d.user.tags[2], "#FFF", 9)
''');
      final ScriptResult r = await engine.executeFile(f.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans.single.text, 'ada:b');
    });

    test('malformed JSON is reported, not crashed', () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/t.lua')
        ..writeAsStringSync('return font(tostring(json.decode("{oops")), "#FFF", 9)');
      final ScriptResult r = await engine.executeFile(f.path);
      // Either a clean parse failure (nil -> "nil") or an engine error is
      // acceptable; a crash or a hang is not, and this prints the useful
      // diagnostic if a future change regresses either.
      expect(r.ok || r.error.isNotEmpty, isTrue);
    });
  });

  group('the APIs that were missing before this rewrite', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('dino_runner.lua runs: sys.watch_keys/key_triggered/key_pressed',
        () async {
      final ScriptResult r = await engine.executeFile(repoFile('scripts/dino_runner.lua'));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.spans, isNotEmpty);
    });

    test('webview_demo.lua runs: is_china, gh_proxy and the webview item',
        () async {
      final ScriptResult r =
          await engine.executeFile(repoFile('scripts/webview_demo.lua'));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.clickAction, ClickAction.dialog);

      final DialogItem? wv =
          r.dialog!.items.where((DialogItem i) => i.type == DialogItemType.webview)
                  .firstOrNull;
      expect(wv, isNotNull,
          reason: 'the demo declares a {type="webview"} item; the engine must '
              'carry it through even though rendering it is a later phase');
      expect(wv!.url, contains('http'));
    });

    test('sys.country() returns the OS region and sys.language() the UI locale',
        () async {
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/u.lua')
        ..writeAsStringSync('return font(sys.country() .. "/" .. sys.language(), "#FFF", 9)');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      // Don't assert a specific locale — that depends on the machine — but a
      // missing API would make this "nil/nil", which is worth catching.
      expect(r.spans.single.text, isNot('nil/nil'));
    });

    test('sys.gh_proxy() rewrites a GitHub URL when it decides CN, else not',
        () async {
      // Whether the machine is considered "in China" depends on geo-IP, which
      // is network-dependent, so accept either branch but prove the function
      // exists and returns a usable string either way.
      final File f = File('${Directory.systemTemp.createTempSync('tp').path}/v.lua')
        ..writeAsStringSync(
            'return font(sys.gh_proxy("https://github.com/a/b"), "#FFF", 9)');
      final ScriptResult r = await engine.executeFile(f.path);

      expect(r.ok, isTrue, reason: r.error);
      final String out = r.spans.single.text;
      expect(out, anyOf(contains('github.com'), contains('gh-proxy.com')));
    });
  });

  group('normalized goldens for the shipped examples', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    /// Every timestamp/date shape these scripts emit, replaced by a marker.
    String normalizeVolatile(String s) => s
        .replaceAll(RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b'), '<TIME>')
        .replaceAll(RegExp(r'\b\d{1,2}/\d{1,2}\b'), '<DATE>')
        .replaceAll(RegExp(r'\b\d+(\.\d+)?\s?([KMGT]?B)\b'), '<SIZE>')
        .replaceAll(RegExp(r'\b\d+(\.\d+)?\s?%'), '<PCT>');

    Future<List<String>> spanSummary(String relPath) async {
      final ScriptResult r = await engine.executeFile(repoFile(relPath));
      return <String>[
        'ok=${r.ok}',
        'err=${normalizeVolatile(r.error)}',
        'n=${r.spans.length}',
        ...r.spans.map((Span s) =>
            '${s.isImage ? "img" : "txt"}:${s.align.name}'
            ':${s.newline ? "nl" : "-"}'
            ':${normalizeVolatile(s.text)}'),
      ];
    }

    test('rich_text_demo.lua keeps its structure', () async {
      // 7 spans, second line starts at span index 3, right-aligned spans at
      // 2 and 6. Pinned here so a change in span/align/newline handling shows
      // up even though the text itself is clock-dependent.
      final List<String> summary = await spanSummary('examples/rich_text_demo.lua');
      expect(summary.first, 'ok=true');
      expect(summary[1], 'err=');
      expect(summary[2], 'n=7');
      expect(summary[3], 'txt:left:-:TIME ');
      // summary[0..2] are the ok/err/n header lines, so span i is summary[i+3].
      //   span 0 'TIME ' left      span 1 clock left
      //   span 2 date    RIGHT  <- line 1's reading
      //   span 3 ''       newline (a flag, not a character)
      //   span 4 'DATE ' left      span 5 date  left
      //   span 6 clock   RIGHT  <- line 2's reading
      expect(summary[5], 'txt:right:-:<DATE>');
      expect(summary[6], 'txt:left:nl:');
      expect(summary[9], 'txt:right:-:<TIME>');
    });

    test('hud_clock.lua produces a clickable dialog', () async {
      final ScriptResult r = await engine.executeFile(repoFile('examples/hud_clock.lua'));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.clickable, isTrue);
      expect(r.clickAction, ClickAction.dialog);
      expect(r.spans.single.text, isNotEmpty);
    });

    test('system_monitor.lua produces a two-line, multi-span bar', () async {
      final List<String> summary = await spanSummary('examples/system_monitor.lua');
      expect(summary.first, 'ok=true');
      // Two lines, one right-aligned reading on each.
      expect(summary.where((String l) => l.contains(':nl:')).length, 1);
      expect(summary.where((String l) => l.contains(':right:')).length, greaterThan(1));
    });
  });

  group('contract-only check for the network-bound script', () {
    late EngineApi engine;
    setUp(() async => engine = await EngineApi.start());
    tearDown(() async => await engine.dispose());

    test('zeeho.lua either succeeds or reports a clean error', () async {
      // It performs a real HTTP request, so content is not asserted. What is
      // asserted is that the engine never crashes and always resolves.
      final ScriptResult r = await engine.executeFile(repoFile('scripts/zeeho.lua'));

      expect(r.ok, isA<bool>());
      if (r.ok) {
        expect(r.spans, isNotEmpty);
      } else {
        expect(r.error, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
