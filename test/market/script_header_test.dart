// The Lua script header parser: `@param` and `@refresh`.
//
// Ports `script_parse_params` / `script_parse_refresh` (`lib/scripting.c:905-990`).
// The load-bearing rule throughout is that the scan STOPS at the first
// non-comment line, so a directive after the first line of code is invisible —
// that is what makes "the header" a well-defined region.

import 'dart:io';

import 'package:taskpin/core/market/script_header.dart';
import 'package:test/test.dart';

void main() {
  group('@param', () {
    test('parses key, type and label', () {
      final List<ScriptParamDecl> decls =
          parseScriptParams('-- @param BASE_URL string API地址(如 https://api.example.com)\n');
      expect(decls, hasLength(1));
      expect(decls.single.key, 'BASE_URL');
      expect(decls.single.type, 'string');
      expect(decls.single.label, 'API地址(如 https://api.example.com)');
    });

    test('the label may contain spaces and is taken to end of line', () {
      final List<ScriptParamDecl> decls =
          parseScriptParams('-- @param A string 多 个 空 格 的 标 签\n');
      expect(decls.single.label, '多 个 空 格 的 标 签');
    });

    test('parses several declarations in order', () {
      const String src = '''
-- docker_status.lua - Docker 容器状态监控
-- @param DOCKER_HOST string Docker Host (默认 unix:///var/run/docker.sock)
-- @param TIMEOUT number 超时秒数
-- @refresh 5000
''';
      final List<ScriptParamDecl> decls = parseScriptParams(src);
      expect(decls.map((ScriptParamDecl d) => d.key).toList(),
          <String>['DOCKER_HOST', 'TIMEOUT']);
      expect(decls[1].type, 'number');
    });

    test('the scan STOPS at the first non-comment line', () {
      // `if (p[0] != '-' || p[1] != '-') break;`
      const String src = '''
-- @param A string first
local x = 1
-- @param B string second
''';
      final List<ScriptParamDecl> decls = parseScriptParams(src);
      expect(decls.map((ScriptParamDecl d) => d.key).toList(), <String>['A']);
    });

    test('a directive on the very first line is parsed', () {
      expect(parseScriptParams('-- @param A string x\n'), hasLength(1));
    });

    test('leading spaces and tabs before the -- are tolerated', () {
      expect(parseScriptParams('   \t-- @param A string x\n'), hasLength(1));
    });

    test('a file with no header comment yields nothing', () {
      expect(parseScriptParams('local x = 1\n'), isEmpty);
      expect(parseScriptParams(''), isEmpty);
    });

    test('an empty label is allowed', () {
      final List<ScriptParamDecl> decls = parseScriptParams('-- @param A string\n');
      expect(decls.single.key, 'A');
      expect(decls.single.type, 'string');
      expect(decls.single.label, '');
    });

    test('a key of 64+ characters is SKIPPED, not truncated', () {
      // `if (klen <= 0 || klen >= 64) continue;`
      final String longKey = 'K' * 64;
      expect(parseScriptParams('-- @param $longKey string x\n'), isEmpty);
      final String okKey = 'K' * 63;
      expect(parseScriptParams('-- @param $okKey string x\n'), hasLength(1));
    });

    test('a type of 16+ characters is clamped to 15', () {
      // `if (tlen >= 16) tlen = 15;`
      final List<ScriptParamDecl> decls =
          parseScriptParams('-- @param A abcdefghijklmnopqrstuvwxyz label\n');
      expect(decls.single.type.length, 15);
      expect(decls.single.type, 'abcdefghijklmno');
    });

    test('a label of 128+ characters is clamped to 127', () {
      final String longLabel = 'L' * 200;
      final List<ScriptParamDecl> decls =
          parseScriptParams('-- @param A string $longLabel\n');
      expect(decls.single.label.length, 127);
    });

    test('maxDecls caps the count (CFG_MAX_PARAMS = 16)', () {
      final StringBuffer buf = StringBuffer();
      for (int i = 0; i < 20; i++) {
        buf.writeln('-- @param K$i string label');
      }
      expect(parseScriptParams(buf.toString()), hasLength(16));
      expect(parseScriptParams(buf.toString(), maxDecls: 3), hasLength(3));
      expect(parseScriptParams(buf.toString(), maxDecls: 0), isEmpty);
    });

    test('a line that merely contains "@param" is not a declaration', () {
      // `strncmp(p, "@param", 6) != 0` requires it to START the line.
      expect(parseScriptParams('-- see @param docs\n'), isEmpty);
      expect(parseScriptParams('-- @parameter string x\n'), hasLength(1),
          reason: 'the C strncmp matches the first 6 chars, so @parameter parses too');
    });

    test('unknown types are stored verbatim (the C parser does not validate)', () {
      final List<ScriptParamDecl> decls =
          parseScriptParams('-- @param A widgetthing label\n');
      expect(decls.single.type, 'widgetthing');
    });
  });

  group('@refresh', () {
    test('parses the milliseconds value', () {
      expect(parseScriptRefresh('-- @refresh 5000\n'), 5000);
      expect(parseScriptRefresh('-- @refresh 30000\n'), 30000);
    });

    test('returns 0 when absent', () {
      expect(parseScriptRefresh('-- docker.lua\n'), 0);
      expect(parseScriptRefresh(''), 0);
    });

    test('only the first @refresh counts', () {
      // The C loop `break`s after the first `atoi`.
      expect(parseScriptRefresh('-- @refresh 1000\n-- @refresh 9999\n'), 1000);
    });

    test('the scan stops at the first non-comment line', () {
      expect(parseScriptRefresh('local x = 1\n-- @refresh 1000\n'), 0);
    });

    test('atoi semantics: trailing junk is ignored', () {
      expect(parseScriptRefresh('-- @refresh 5000ms\n'), 5000);
      expect(parseScriptRefresh('-- @refresh 5000 # every 5s\n'), 5000);
    });

    test('atoi semantics: unparseable yields 0', () {
      expect(parseScriptRefresh('-- @refresh\n'), 0);
      expect(parseScriptRefresh('-- @refresh abc\n'), 0);
    });

    test('atoi semantics: a negative value is returned as-is', () {
      // The installer's floor turns this into the 5000 default.
      expect(parseScriptRefresh('-- @refresh -1\n'), -1);
    });

    test('tabs separate the directive from the value', () {
      expect(parseScriptRefresh('-- @refresh\t7000\n'), 7000);
    });
  });

  group('headerCommentLines', () {
    test('returns the leading comment block with markers stripped', () {
      const String src = '-- a\n-- b\nlocal x = 1\n-- c\n';
      expect(headerCommentLines(src), <String>['a', 'b']);
    });

    test('handles CRLF line endings', () {
      expect(headerCommentLines('-- a\r\n-- b\r\nlocal x = 1\r\n'), <String>['a', 'b']);
    });

    test('an empty header yields nothing', () {
      expect(headerCommentLines('local x = 1'), isEmpty);
      expect(headerCommentLines(''), isEmpty);
    });
  });

  group('against the real scripts in the repo', () {
    // Reading the shipped scripts is the check that the parser handles headers
    // written by humans rather than by this test suite.
    final List<String> paths = <String>[
      'scripts/zeeho.lua',
      'scripts/webview_demo.lua',
      'scripts/dino_runner.lua',
      'examples/zeeho.lua',
      'examples/system_monitor.lua',
      'examples/zentao_task.lua',
    ];

    test('every shipped script parses without throwing', () async {
      for (final String path in paths) {
        final File f = File(path);
        if (!f.existsSync()) continue; // a missing example is not this test's job
        final String src = f.readAsStringSync();
        // Must not throw, whatever the header looks like.
        expect(() => parseScriptParams(src), returnsNormally, reason: path);
        expect(() => parseScriptRefresh(src), returnsNormally, reason: path);
      }
    });

    test('zeeho.lua yields its VIN param and 30 s refresh', () async {
      final File f = File('scripts/zeeho.lua');
      if (!f.existsSync()) return;
      final String src = f.readAsStringSync();
      final List<ScriptParamDecl> decls = parseScriptParams(src);
      expect(decls.map((ScriptParamDecl d) => d.key), contains('VIN'));
      expect(parseScriptRefresh(src), 30000);
    });

    test('dino_runner.lua has no @param and no @refresh', () async {
      // Its header is `-- dino_runner.lua ...`, `-- @realtime`, `-- @bar_width 360`
      // — none of which the C parser knows about.
      final File f = File('scripts/dino_runner.lua');
      if (!f.existsSync()) return;
      final String src = f.readAsStringSync();
      expect(parseScriptParams(src), isEmpty);
      expect(parseScriptRefresh(src), 0);
    });
  });
}
