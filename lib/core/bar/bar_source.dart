// Turning a pinned item into spans.
//
// One item has one of two shapes, and both must end up as a `TpBarContent`:
//
//   Lua item   `lua_path` names a script. Run it, take its spans.
//   URL item   `url` is fetched, then `field_expr` picks values out of the JSON
//              body. This is the template mode: the expression is Lua with the
//              raw body bound to the global `response`, and `extract_fields`
//              is the fallback when the expression is not valid Lua.
//
// That two-step (fetch, then evaluate) is what `src/bar_window.c:245-290` does,
// and this reproduces it: a URL item whose `field_expr` parses as Lua is
// evaluated by the engine with `response` set; if that produces no spans, the
// `$.path` substitution is applied to the raw body instead.
//
// Failure is a VALUE here, not an exception. `ScriptResult.error` exists
// precisely so a Lua traceback is never rendered onto the bar
// (`native/engine/taskpin_engine.h`), and the controller turns [failed] into the
// error state stripe.

import 'dart:convert';

import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart';

import '../config/config_schema.dart';
import '../market/http_fetcher.dart';

/// What one resolution produced.
class ResolvedBarContent {
  const ResolvedBarContent({
    required this.content,
    this.failed = false,
    this.error,
    this.result,
  });

  final TpBarContent content;

  /// True when the script errored or the fetch did not succeed. Drives the
  /// danger state stripe.
  final bool failed;

  /// The failure text, for the diagnostics page. NEVER placed on the bar.
  final String? error;

  /// The full script result, when one was produced. The click path needs
  /// `clickable` / `click_action` / `click_url` from it, which the span list
  /// does not carry.
  final ScriptResult? result;
}

/// Resolve one item to the spans the bar should draw.
Future<ResolvedBarContent> resolveContent({
  required EngineApi engine,
  required PinItem item,
  required HttpFetcher fetcher,
  String? baseDirectory,
}) async {
  if (item.type == PinItemType.lua) {
    return _resolveLua(engine, item, baseDirectory);
  }
  return _resolveUrl(engine, item, fetcher);
}

Future<ResolvedBarContent> _resolveLua(
  EngineApi engine,
  PinItem item,
  String? baseDirectory,
) async {
  final String path = resolveScriptPath(item.luaPath, baseDirectory);
  if (path.isEmpty) {
    return const ResolvedBarContent(
      content: TpBarContent(),
      failed: true,
      error: 'no lua_path',
    );
  }

  final ScriptResult result;
  try {
    result = await engine.executeFile(path, argsJson: buildArgsJson(item));
  } on Object catch (e) {
    // A transport failure (isolate died, library unloaded), not a Lua error.
    return ResolvedBarContent(
      content: TpBarContent(),
      failed: true,
      error: e.toString(),
    );
  }

  return ResolvedBarContent(
    content: toBarContent(result),
    failed: !result.ok,
    error: result.ok ? null : result.error,
    result: result,
  );
}

Future<ResolvedBarContent> _resolveUrl(
  EngineApi engine,
  PinItem item,
  HttpFetcher fetcher,
) async {
  if (item.url.isEmpty) {
    return const ResolvedBarContent(
      content: TpBarContent(),
      failed: true,
      error: 'no url',
    );
  }

  final HttpResult response = await fetcher.getText(
    item.url,
    headers: parseHeaderBlock(item.reqHeaders),
  );
  if (!response.isSuccess) {
    return ResolvedBarContent(
      content: TpBarContent(),
      failed: true,
      error: 'HTTP ${response.statusCode}',
    );
  }

  // No expression: the body IS the display text, verbatim.
  if (item.fieldExpr.isEmpty) {
    return ResolvedBarContent(
      content: TpBarContent(
        spans: <TpBarSpan>[TpBarSpan(text: response.body.trim())],
      ),
    );
  }

  // Template mode: the engine evaluates the expression with `response` bound.
  // A `$.path` expression is not valid Lua, so the engine reports an error —
  // which is the signal to fall back to field substitution, the same order the
  // C layer uses (`src/bar_window.c:270-275`).
  ScriptResult? result;
  try {
    result = await engine.executeTemplate(
      item.fieldExpr,
      responseRaw: response.body,
    );
  } on Object {
    result = null;
  }

  if (result != null && result.ok && result.spans.isNotEmpty) {
    return ResolvedBarContent(content: toBarContent(result), result: result);
  }

  // Either not Lua, or Lua that produced nothing. `$.path` substitution is the
  // documented meaning of `field_expr` for the common case, so this is NOT
  // reported as a failure: a `$.missing` path is left as literal text, exactly
  // as `extract_fields` does.
  final String extracted = extractFields(response.body, item.fieldExpr);
  return ResolvedBarContent(
    content: TpBarContent(spans: <TpBarSpan>[TpBarSpan(text: extracted.trim())]),
  );
}

/// `ScriptResult.spans` -> `TpBarContent`.
///
/// The engine's `Span.color` is `"#RRGGBB"` / `""`; `TpBarSpan.color` is a
/// nullable `Color`. `TpBarSpan.parseWireColor` is the shared converter, so the
/// bar and the manager's preview agree on what a colour string means.
TpBarContent toBarContent(ScriptResult result) => TpBarContent(
  spans: result.spans
      .map(
        (Span s) => TpBarSpan(
          text: s.text,
          color: TpBarSpan.parseWireColor(s.color),
          fontSize: s.fontSize,
          align: TpSpanAlign.fromAbi(s.align.wireValue),
          newline: s.newline,
          isImage: s.isImage,
          imageWidth: s.imageWidth,
          imageHeight: s.imageHeight,
        ),
      )
      .toList(growable: false),
);

/// `PinItem.params` -> the `args` table JSON the engine binds.
///
/// `lib/scripting.c:846-857` builds the global `args` table from the item's
/// params, skipping any with an empty key. Only the key/value pair matters —
/// the label is UI metadata.
String buildArgsJson(PinItem item) {
  final Map<String, String> args = <String, String>{};
  for (final ParamEntry p in item.params) {
    if (p.key.isNotEmpty) {
      args[p.key] = p.value;
    }
  }
  return jsonEncode(args);
}

/// `req_headers` is a raw block, one `Key: Value` per line (`lib/httputil.c`).
/// Blank lines and lines without a colon are skipped rather than producing an
/// empty header name, which `package:http` rejects.
Map<String, String> parseHeaderBlock(String raw) {
  final Map<String, String> out = <String, String>{};
  for (final String line in raw.split(RegExp(r'\r?\n'))) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final int colon = trimmed.indexOf(':');
    if (colon <= 0) continue;
    out[trimmed.substring(0, colon).trim()] = trimmed.substring(colon + 1).trim();
  }
  return out;
}

/// Resolve a script path against the config directory.
///
/// Scripts are stored both absolute (what the editor writes) and relative to
/// the config's base directory (what a hand-edited or migrated config carries),
/// so both must work.
String resolveScriptPath(String path, String? baseDirectory) {
  if (path.isEmpty) return '';
  if (baseDirectory == null || baseDirectory.isEmpty) return path;
  if (path.length > 1 && path[1] == ':') return path; // Windows drive letter
  if (path.startsWith('/') || path.startsWith(r'\')) return path;
  final String sep = baseDirectory.endsWith(r'\') || baseDirectory.endsWith('/')
      ? ''
      : r'\';
  return '$baseDirectory$sep$path';
}

/// Decode a JSON body and pull out the `$.path` fields a `field_expr` asks for.
///
/// A faithful port of `extract_fields` (`src/expression.c`): literal text
/// passes through, a `$.a.b` token is replaced by the value at that path, and a
/// path that does not resolve is left AS THE LITERAL TEXT — that is the C
/// behaviour, and it is not an error. Arrays and objects render as `[...]` and
/// `{...}`, matching `json_node_to_string`.
///
/// The token ends at whitespace, a comma or a newline, exactly like the C
/// scanner, so `"CPU $.cpu, MEM $.mem"` is two tokens.
String extractFields(String raw, String expr) {
  if (expr.isEmpty) {
    return raw;
  }
  Object? root;
  try {
    root = jsonDecode(raw);
  } on FormatException {
    root = null;
  }

  final StringBuffer out = StringBuffer();
  final RegExp token = RegExp(r'\$\.[^\s,\n\r]*');
  int cursor = 0;
  for (final RegExpMatch m in token.allMatches(expr)) {
    out.write(expr.substring(cursor, m.start));
    cursor = m.end;
    final String path = m.group(0)!;
    out.write(root == null ? path : (_stringifyPath(root, path) ?? path));
  }
  out.write(expr.substring(cursor));
  return out.toString();
}

/// Walk a `$.a.b[0]` path. Returns null when it does not resolve.
String? _stringifyPath(Object? root, String path) {
  Object? cur = root;
  String rest = path.startsWith(r'$.') ? path.substring(2) : path;
  if (rest.isEmpty) {
    return null;
  }
  while (rest.isNotEmpty && cur != null) {
    final int bracket = rest.indexOf('[');
    final int dot = rest.indexOf('.');
    int next = rest.length;
    if (bracket >= 0 && bracket < next) next = bracket;
    if (dot >= 0 && dot < next) next = dot;

    final String key = rest.substring(0, next);
    if (key.isNotEmpty) {
      if (cur is! Map) return null;
      cur = cur[key];
    }
    rest = rest.substring(next);

    if (rest.startsWith('[')) {
      final int close = rest.indexOf(']');
      if (close < 0) return null;
      final int? idx = int.tryParse(rest.substring(1, close));
      if (idx == null || cur is! List || idx < 0 || idx >= cur.length) {
        return null;
      }
      cur = cur[idx];
      rest = rest.substring(close + 1);
    }
    if (rest.startsWith('.')) {
      rest = rest.substring(1);
    }
  }
  return _stringifyNode(cur);
}

String? _stringifyNode(Object? node) {
  if (node == null) return 'null';
  if (node is bool) return node ? 'true' : 'false';
  if (node is num) {
    // `json_node_to_string` prints an integral double without a decimal point.
    if (node is double && node == node.truncateToDouble()) {
      return node.toInt().toString();
    }
    return node.toString();
  }
  if (node is String) return node;
  if (node is List) return '[...]';
  if (node is Map) return '{...}';
  return node.toString();
}

/// The engine's `DialogSpec` -> the JSON shape the dialog window parses.
///
/// The two models are different types in different packages: the engine's is a
/// copy of the C ABI (`TPScriptResult.dialog`), the window's is
/// `features/dialogs/dialog_spec.dart`, which `DialogSpec.fromJson` reads. The
/// key names here are the engine's own (`native/engine/taskpin_engine.h`), which
/// is what that parser expects.
///
/// Returns null when there is nothing to show — an empty item list would open a
/// blank window, which is worse than doing nothing.
Map<String, dynamic>? dialogSpecToJson(DialogSpec spec) {
  if (spec.items.isEmpty) {
    return null;
  }
  return <String, dynamic>{
    'title': spec.title,
    'width': spec.width,
    'height': spec.height,
    'refresh': spec.refresh,
    'borderless': spec.borderless,
    'clickthrough': spec.clickthrough,
    'opacity': spec.opacity,
    'bg_color': spec.backgroundColor,
    'transparent_bg': spec.transparentBackground,
    'item_count': spec.items.length,
    'items': spec.items.map(_dialogItemToJson).toList(growable: false),
  };
}

Map<String, dynamic> _dialogItemToJson(DialogItem item) => <String, dynamic>{
  'type': item.type.wireValue,
  'value': item.value,
  'color': item.color,
  'size': item.fontSize,
  'bold': item.bold,
  'image': item.image,
  'img_w': item.imageWidth,
  'img_h': item.imageHeight,
  'url': item.url,
  'cmd': item.cmd,
  'bg': item.bg,
  'web_w': item.webWidth,
  'web_h': item.webHeight,
  'columns': item.columns,
  'rows': item.rows,
  'row_urls': item.rowUrls,
  'row_cmds': item.rowCmds,
};
