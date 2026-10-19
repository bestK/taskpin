// Lua script header parsing: `@param`, `@refresh`, and the admin directive.
//
// Ports `script_parse_params` and `script_parse_refresh` from `lib/scripting.c`
// (lines 905-990) token-for-token, because the market installer uses them to
// seed a downloaded item's `interval_ms` and `params` — exactly what the C fix in
// commit 4f5165c (`src/ui_market_view.cpp`) does.
//
// The header grammar, as the C parser actually implements it:
//
//   * Only leading lines that begin with `--` are considered. The scan STOPS at
//     the first line that is not a comment (`if (p[0] != '-' || p[1] != '-')
//     break;`), so a directive after the first line of code is ignored. This is
//     the load-bearing rule: a `-- @refresh` inside a function body does nothing.
//   * Leading spaces/tabs are skipped on every line.
//   * `@param <key> <type> <label>` — the key is the first whitespace-delimited
//     token, the type the second, and the label is the REST OF THE LINE
//     (trimmed of CR/LF). A label containing spaces is therefore preserved.
//   * A key of 64 characters or more is skipped (`klen >= 64` -> `continue`),
//     not truncated.
//   * The type is clamped to 15 characters.
//   * The label is clamped to 127 characters.
//   * `@refresh <ms>` parses with `atoi` semantics: leading whitespace skipped,
//     optional sign, then leading digits; anything unparseable yields 0.
//
// The admin directive (`@admin`) is NOT from the C code — see elevate_trigger.dart
// for why it exists and how it is isolated.
//
// Pure Dart (`dart:io` for file reads only).

import 'dart:convert' show LineSplitter;
import 'dart:io';

/// One `@param` declaration.
///
/// Mirrors `ScriptParamDecl` (`lib/scripting.h`): `key`, `type`, `label`. The
/// Dart config model stores these as `ParamEntry { key, value, label }` — the
/// declared `type` is a UI hint that the C config never persists, which is why
/// it is parsed here but not written to `PinItem.params`.
class ScriptParamDecl {
  const ScriptParamDecl({
    required this.key,
    required this.type,
    required this.label,
  });

  final String key;

  /// The declared type token: `string`, `number`, `boolean`, `color`, `path`,
  /// `file`, ... The C parser stores it verbatim without validating it, so this
  /// does too. `TpParamType.fromWire` maps an unknown token to `string`.
  final String type;

  /// The human label. May be empty when the declaration omits it.
  final String label;

  @override
  String toString() => 'ScriptParamDecl($key, $type, "$label")';

  @override
  bool operator ==(Object other) =>
      other is ScriptParamDecl &&
      other.key == key &&
      other.type == type &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, type, label);
}

/// The field limits the C parser enforces.
class ScriptHeaderLimits {
  const ScriptHeaderLimits._();

  /// `klen >= 64` -> the declaration is skipped.
  static const int maxKeyLength = 64;

  /// `if (tlen >= 16) tlen = 15;`
  static const int maxTypeLength = 16;

  /// `if (llen >= 128) llen = 127;`
  static const int maxLabelLength = 128;

  /// The C `fgets(line, sizeof(line), f)` buffer. A directive longer than this
  /// is split across two "lines" by the C reader, producing garbage; we read
  /// whole lines, which is strictly better and cannot produce a false negative
  /// on a real script.
  static const int cLineBuffer = 512;
}

/// The leading `--` comment block of a script, with the `--` marker removed and
/// each line left-trimmed.
///
/// This is the region both `parseScriptParams` and `parseScriptRefresh` scan,
/// and it is exposed so other header consumers (the admin directive in
/// `lib/core/elevate/elevate_trigger.dart`) share the exact same stopping rule.
/// Duplicating the rule is how two parsers end up disagreeing about where the
/// header ends.
///
/// The scan STOPS at the first line that is not a comment — the C behaviour
/// (`if (p[0] != '-' || p[1] != '-') break;`).
List<String> headerCommentLines(String source) {
  final List<String> out = <String>[];
  for (final String rawLine in const LineSplitter().convert(source)) {
    final String line = rawLine.trimLeft();
    if (!line.startsWith('--')) break;
    out.add(line.substring(2).trimLeft());
  }
  return out;
}

/// Parses `@param` declarations from a script header.
///
/// [maxDecls] mirrors the C `max_decls` argument (`CFG_MAX_PARAMS` = 16 in
/// practice). Extra declarations beyond the cap are ignored, matching the
/// `count < max_decls` loop guard.
List<ScriptParamDecl> parseScriptParams(String source, {int maxDecls = 16}) {
  final List<ScriptParamDecl> out = <ScriptParamDecl>[];
  if (maxDecls <= 0) return out;

  for (final String stripped in headerCommentLines(source)) {
    String p = stripped;
    if (!p.startsWith('@param')) continue;
    p = p.substring(6).trimLeft();

    // key
    final int keyEnd = _tokenEnd(p);
    final String key = p.substring(0, keyEnd);
    if (key.isEmpty || key.length >= ScriptHeaderLimits.maxKeyLength) continue;
    p = p.substring(keyEnd).trimLeft();

    // type
    final int typeEnd = _tokenEnd(p);
    String type = p.substring(0, typeEnd);
    if (type.length >= ScriptHeaderLimits.maxTypeLength) {
      type = type.substring(0, ScriptHeaderLimits.maxTypeLength - 1);
    }
    p = p.substring(typeEnd).trimLeft();

    // label = the rest of the line, minus trailing CR/LF (already handled by
    // LineSplitter) and clamped.
    String label = p.trimRight();
    if (label.length >= ScriptHeaderLimits.maxLabelLength) {
      label = label.substring(0, ScriptHeaderLimits.maxLabelLength - 1);
    }

    out.add(ScriptParamDecl(key: key, type: type, label: label));
    if (out.length >= maxDecls) break;
  }
  return out;
}

/// Parses `@refresh <ms>` from a script header.
///
/// Returns 0 when absent or unparseable, exactly like the C function. Note the
/// C version returns on the FIRST `@refresh` it sees (`break;` after `atoi`), so
/// a second directive is ignored.
int parseScriptRefresh(String source) {
  for (final String stripped in headerCommentLines(source)) {
    String p = stripped;
    if (!p.startsWith('@refresh')) continue;
    p = p.substring(8).trimLeft();
    return _atoi(p);
  }
  return 0;
}

/// Reads a file as UTF-8 and parses its `@param` declarations.
///
/// Returns an empty list when the file cannot be read, matching
/// `script_parse_params`'s `if (!f) return 0`.
Future<List<ScriptParamDecl>> parseScriptParamsFile(
  String path, {
  int maxDecls = 16,
}) async {
  final String source = await _readOrEmpty(path);
  return parseScriptParams(source, maxDecls: maxDecls);
}

/// Reads a file as UTF-8 and parses its `@refresh`.
Future<int> parseScriptRefreshFile(String path) async =>
    parseScriptRefresh(await _readOrEmpty(path));

Future<String> _readOrEmpty(String path) async {
  try {
    final File file = File(path);
    if (!file.existsSync()) return '';
    // allowMalformed: a script saved as GBK must not throw here. The C reader
    // is byte-oriented and cannot fail, so failing would be a regression.
    return await file.readAsString();
  } catch (_) {
    return '';
  }
}

/// Index of the end of the first whitespace-delimited token.
int _tokenEnd(String s) {
  for (int i = 0; i < s.length; i++) {
    final int c = s.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) return i;
  }
  return s.length;
}

/// C `atoi` semantics: skip leading whitespace, accept an optional sign, then
/// take leading digits. Anything else is 0.
int _atoi(String s) {
  int i = 0;
  while (i < s.length) {
    final int c = s.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
    } else {
      break;
    }
  }
  bool negative = false;
  if (i < s.length && (s[i] == '-' || s[i] == '+')) {
    negative = s[i] == '-';
    i++;
  }
  int value = 0;
  bool any = false;
  while (i < s.length) {
    final int c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) break;
    value = value * 10 + (c - 0x30);
    any = true;
    i++;
  }
  if (!any) return 0;
  return negative ? -value : value;
}
