// Lua script header parsing: `-- @param` and `-- @refresh`.
//
// ---------------------------------------------------------------------------
// DEPRECATED PARSER. The engine is the authority now.
// ---------------------------------------------------------------------------
// The editor no longer calls the `parseLuaHeader*` functions below. It reads the
// header through `EngineApi.parseParams` / `EngineApi.parseRefresh` (the real
// `tp_parse_params` / `tp_parse_refresh`), which is the same parser the taskbar
// uses to bind `args` — so the form and the running bar can no longer disagree.
//
// What remains here, and is still imported:
//
//   * [LuaHeader] / [LuaHeaderParam] — the editor's display shape. The editor
//     adapts the engine's `ParamDecl` list into these and `param_merge.dart`
//     merges them with the stored values. They are a plain data holder, not a
//     parser, and are intentionally kept so the merge layer stays engine-free.
//
// The three `parseLuaHeader*` entry points are retained (deprecated) rather than
// deleted because a second consumer — the market installer, via
// `lib/core/market/script_header.dart` — still ports the same grammar for a
// path that runs before the engine is guaranteed to be up. See the note below.
//
// The authoritative implementation is `tp_parse_params` / `tp_parse_refresh` in
// `native/engine/tp_engine.c` (lines 255-354), now reachable over dart:ffi as
// `EngineApi.parseParams`. The functions here are byte-for-byte ports of that C
// code and are kept only for reference and for the tests that pin the grammar.
//
// NOTE — A SECOND DART PORT EXISTS. `lib/core/market/script_header.dart` ports
// the same grammar for the market installer, from `lib/scripting.c:905-990`.
// That function and `tp_engine.c` are byte-identical in their parsing logic, so
// the two Dart ports agree on the grammar. The market keeps its own copy because
// it parses a script it has just downloaded, before any item (and therefore any
// engine call) exists for it.
//
// It is written to be BYTE-FOR-BYTE COMPATIBLE with the C original, because a
// mismatch here means the editor shows different fields than the engine will
// actually bind. The C behaviour that is easy to get wrong, and which is
// reproduced deliberately:
//
//   1. Lines are read with a 512-byte ceiling (`TP_HDR_LINE`), exactly like
//      `fgets(line, 512, f)`. A longer line is therefore SPLIT, and the
//      remainder is examined as if it were the next line — where it will not
//      start with `--` and will terminate the scan. Getting this wrong would
//      make us find params the engine does not.
//   2. The scan stops at the first line that is not a `--` comment. The header
//      must be contiguous at the top of the file.
//   3. Everything is done in BYTES. `key` is dropped when empty or >= 64 bytes;
//      `type` is truncated to 15; `label` to 127. Truncating a UTF-8 label at a
//      byte boundary can split a character, and that is what the C code does.
//   4. After `--` only SPACES are skipped (not tabs) before matching `@param`;
//      between fields both spaces and tabs are skipped. A TAB DIRECTLY AFTER
//      `@param` is therefore not skipped, which makes the key empty and causes
//      the whole declaration to be silently dropped. That is the C behaviour
//      (verified by reading tp_engine.c:295-302) and it is reproduced here, not
//      "fixed": a script that relies on it being dropped, or a bug report about
//      a missing field, should behave identically in both implementations.
//   5. A leading UTF-8 BOM is skipped so the first line is still a comment
//      (`tp_engine.c:217`).
//
// This file imports only `dart:convert`, `dart:io` and `dart:typed_data` so it
// stays unit testable and analysable without the Flutter SDK.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One `-- @param <key> <type> <label>` declaration, as the engine parses it.
///
/// Mirrors `TPParamDecl` (`native/engine/taskpin_engine.h`), including the field
/// widths: key 64, type 16, label 128.
class LuaHeaderParam {
  const LuaHeaderParam({
    required this.key,
    required this.type,
    required this.label,
  });

  /// The name the script reads it by. Never empty, never >= 64 bytes.
  final String key;

  /// The declared type token, e.g. `string`, `number`, `color`. May be empty
  /// when the declaration omitted it; truncated to 15 bytes.
  final String type;

  /// Human label, truncated to 127 bytes. May be empty.
  final String label;

  @override
  String toString() => 'LuaHeaderParam($key, $type, $label)';
}

/// Everything the header declares for one script.
class LuaHeader {
  const LuaHeader({required this.params, required this.refreshMs});

  /// Declarations in file order. The engine's `tp_parse_params` returns them in
  /// this order too, and the editor renders them in this order.
  final List<LuaHeaderParam> params;

  /// `-- @refresh <ms>`, or 0 when not declared. 0 means "no declaration" —
  /// `tp_parse_refresh` returns 0 in that case as well, so a script cannot
  /// declare a 0 ms refresh and be distinguishable from one that declares
  /// nothing. That ambiguity is the C contract; it is preserved here.
  final int refreshMs;

  static const LuaHeader empty = LuaHeader(params: <LuaHeaderParam>[], refreshMs: 0);

  bool get isEmpty => params.isEmpty && refreshMs == 0;

  @override
  String toString() => 'LuaHeader(${params.length} params, refresh=$refreshMs)';
}

/// The `fgets` line ceiling. `#define TP_HDR_LINE 512` in tp_engine.c.
const int _kHeaderLineCap = 512;

/// Field widths from `TPParamDecl`.
const int _kMaxKey = 64;
const int _kMaxType = 16;
const int _kMaxLabel = 128;

/// Parses `-- @param` declarations from a script.
///
/// [maxDecls] mirrors the `max_decls` argument: the C side stops once it has
/// filled the caller's array. Pass [defaultMaxParams] (16, `CFG_MAX_PARAMS`)
/// to match what the config layer can store.
///
/// Never throws: a missing or unreadable file yields [LuaHeader.empty], which is
/// what `tp_parse_params` does when `fopen` fails.
@Deprecated('Use EngineApi.parseParams — the engine is the authority.')
LuaHeader parseLuaHeader(String path, {int maxDecls = defaultMaxParams}) {
  final Uint8List bytes;
  try {
    bytes = File(path).readAsBytesSync();
  } on FileSystemException {
    return LuaHeader.empty;
  }
  return parseLuaHeaderBytes(bytes, maxDecls: maxDecls);
}

/// The async form, for the UI.
///
/// The file read is moved off the frame so a large script on a slow disk cannot
/// jank the editor. The parse itself is identical.
@Deprecated('Use EngineApi.parseParams — the engine is the authority.')
Future<LuaHeader> parseLuaHeaderAsync(
  String path, {
  int maxDecls = defaultMaxParams,
}) async {
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on FileSystemException {
    return LuaHeader.empty;
  }
  return parseLuaHeaderBytes(bytes, maxDecls: maxDecls);
}

/// The byte-level parser, separated so tests need no filesystem.
LuaHeader parseLuaHeaderBytes(
  Uint8List rawBytes, {
  int maxDecls = defaultMaxParams,
}) {
  final Uint8List bytes = _stripBom(rawBytes);
  final List<LuaHeaderParam> params = <LuaHeaderParam>[];
  int refreshMs = 0;

  final _LineReader reader = _LineReader(bytes);

  while (params.length < maxDecls) {
    final Uint8List? line = reader.next(_kHeaderLineCap);
    if (line == null) break; // EOF

    int p = 0;
    // `while (*p == ' ' || *p == '\t') p++;`
    while (p < line.length && (line[p] == 0x20 || line[p] == 0x09)) {
      p++;
    }
    // `if (p[0] != '-' || p[1] != '-') break;`
    if (p + 1 >= line.length || line[p] != 0x2D || line[p + 1] != 0x2D) {
      break;
    }
    p += 2;
    // `while (*p == ' ') p++;` — SPACES ONLY, no tabs.
    while (p < line.length && line[p] == 0x20) {
      p++;
    }

    if (_startsWith(line, p, '@param')) {
      p += 6;
      while (p < line.length && line[p] == 0x20) {
        p++;
      }

      final _Field key = _readToken(line, p);
      p = key.end;
      if (key.length <= 0 || key.length >= _kMaxKey) {
        // The C code `continue`s here — the malformed declaration is skipped
        // but the scan carries on to the next line.
        continue;
      }

      while (p < line.length && (line[p] == 0x20 || line[p] == 0x09)) {
        p++;
      }
      final _Field type = _readToken(line, p);
      p = type.end;

      while (p < line.length && (line[p] == 0x20 || line[p] == 0x09)) {
        p++;
      }
      final _Field label = _readRestOfLine(line, p);

      params.add(LuaHeaderParam(
        key: _utf8(line, key.start, key.length),
        type: _utf8(line, type.start, type.length.clamp(0, _kMaxType - 1)),
        label: _utf8(line, label.start, label.length.clamp(0, _kMaxLabel - 1)),
      ));
      continue;
    }

    if (_startsWith(line, p, '@refresh')) {
      p += 8;
      while (p < line.length && (line[p] == 0x20 || line[p] == 0x09)) {
        p++;
      }
      // `atoi`: optional sign, then leading digits, stopping at anything else.
      refreshMs = _atoi(line, p);
      // `break` — the C code takes the first match and stops scanning.
      break;
    }
    // Any other `--` comment: keep scanning.
  }

  return LuaHeader(params: params, refreshMs: refreshMs);
}

/// `CFG_MAX_PARAMS` from `lib/config.h`. The config layer can only store 16.
const int defaultMaxParams = 16;

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/// Reads the stream the way `fgets(buf, cap, f)` does: at most `cap - 1` bytes,
/// stopping after a newline (which is included), and returning null at EOF.
///
/// This is what produces the "a long line is split" behaviour described above,
/// so it must not be "simplified" into a `split('\n')`.
class _LineReader {
  _LineReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  Uint8List? next(int cap) {
    if (_offset >= _bytes.length) return null;
    final int max = cap - 1; // fgets leaves room for the NUL
    final int start = _offset;
    int end = _offset;
    while (end < _bytes.length && end - start < max) {
      final int b = _bytes[end];
      end++;
      if (b == 0x0A) break; // newline is included in the buffer
    }
    _offset = end;
    return Uint8List.sublistView(_bytes, start, end);
  }
}

class _Field {
  const _Field(this.start, this.length, this.end);
  final int start;
  final int length;
  final int end;
}

/// A token ending at a space, tab, newline or the end of the buffer — the C
/// loop's `while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;`.
_Field _readToken(Uint8List line, int from) {
  int p = from;
  while (p < line.length &&
      line[p] != 0x20 &&
      line[p] != 0x09 &&
      line[p] != 0x0A) {
    p++;
  }
  return _Field(from, p - from, p);
}

/// The rest of the line with trailing CR/LF stripped, as the label loop does.
_Field _readRestOfLine(Uint8List line, int from) {
  int len = line.length - from;
  while (len > 0) {
    final int b = line[from + len - 1];
    if (b == 0x0A || b == 0x0D) {
      len--;
    } else {
      break;
    }
  }
  return _Field(from, len < 0 ? 0 : len, line.length);
}

bool _startsWith(Uint8List line, int at, String ascii) {
  if (at + ascii.length > line.length) return false;
  for (int i = 0; i < ascii.length; i++) {
    if (line[at + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

/// `atoi`: optional whitespace and sign, then digits until a non-digit.
int _atoi(Uint8List line, int from) {
  int p = from;
  while (p < line.length && (line[p] == 0x20 || line[p] == 0x09)) {
    p++;
  }
  bool negative = false;
  if (p < line.length && (line[p] == 0x2B || line[p] == 0x2D)) {
    negative = line[p] == 0x2D;
    p++;
  }
  int value = 0;
  bool any = false;
  while (p < line.length && line[p] >= 0x30 && line[p] <= 0x39) {
    value = value * 10 + (line[p] - 0x30);
    any = true;
    p++;
  }
  if (!any) return 0;
  return negative ? -value : value;
}

/// Decodes a byte slice as UTF-8, replacing malformed sequences rather than
/// throwing — a script with a mangled header must still yield its other params.
String _utf8(Uint8List bytes, int start, int length) {
  if (length <= 0 || start < 0 || start >= bytes.length) return '';
  final int end = (start + length).clamp(start, bytes.length);
  return const Utf8Decoder(allowMalformed: true)
      .convert(Uint8List.sublistView(bytes, start, end));
}

/// Drops a leading UTF-8 BOM, matching `tp_engine.c:217`.
Uint8List _stripBom(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return Uint8List.sublistView(bytes, 3);
  }
  return bytes;
}
