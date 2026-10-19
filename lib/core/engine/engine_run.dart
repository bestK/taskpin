// Turning an engine `ScriptResult` into the design system's bar model, and the
// item's `params` into the `args` JSON the engine binds.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS FILE EXISTS
// ─────────────────────────────────────────────────────────────────────────────
// `packages/taskpin_engine` returns `ScriptResult` (engine `Span`s, a plain
// `display` fallback, an `error` string). The manager UI renders
// `TpBarPreviewStrip`, which consumes `TpBarContent` / `TpBarSpan` from
// `taskpin_design` — the SAME span model the native taskbar renderer draws. The
// conversion between the two lives here, in one place, so the editor and any
// future diagnostics view cannot disagree about what a span means.
//
// The rule the engine's ABI is built around, and which this file must not
// undermine: **a Lua error is never painted onto the bar.** `ScriptResult.error`
// is carried through untouched and rendered by the caller as an error state;
// `barContentFromResult` only ever looks at `spans`/`display`, never at `error`.
//
// Pure logic (no `dart:io`, no Flutter widgets). `taskpin_design`'s models are
// `dart:ui`-only and `taskpin_engine`'s models are `dart:ffi`-only, so this is
// unit-testable under `flutter test` without a running engine or a widget tree.

import 'dart:convert';

import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart' show ScriptResult, Span;

import '../config/config_schema.dart';

/// One engine `Span` as the design system's bar span.
///
/// The two models mirror the same C struct, so this is a field-for-field copy
/// except for the colour: the engine speaks `"#RRGGBB"` (or `""`), and
/// `TpBarSpan` uses a nullable `Color`. An empty or malformed colour becomes
/// `null` ("use the token default") rather than black.
TpBarSpan barSpanFromEngine(Span s) => TpBarSpan(
      text: s.text,
      color: TpBarSpan.parseWireColor(s.color),
      fontSize: s.fontSize,
      align: TpSpanAlign.fromAbi(s.align.wireValue),
      newline: s.newline,
      isImage: s.isImage,
      imageWidth: s.imageWidth,
      imageHeight: s.imageHeight,
    );

/// The bar content to preview for a completed run.
///
/// Prefers the rich `spans` (what the taskbar draws). When a script returned
/// only a plain string, the engine fills `display` and leaves `spans` empty, so
/// that is rendered as a single default-styled span. A failed run still produces
/// whatever partial output it managed, which is why this does not consult
/// `ok`/`error` — the caller decides how to surface the error.
TpBarContent barContentFromResult(ScriptResult result) {
  if (result.spans.isNotEmpty) {
    return TpBarContent(spans: <TpBarSpan>[
      for (final Span s in result.spans) barSpanFromEngine(s),
    ]).clamped();
  }
  if (result.display.isNotEmpty) {
    return TpBarContent(spans: <TpBarSpan>[TpBarSpan(text: result.display)]);
  }
  return const TpBarContent();
}

/// Serialises an item's `params` into the `args` JSON object the engine binds to
/// the Lua global `args`.
///
/// Returns `''` when there is nothing to send, which `executeFile` treats as an
/// empty table (the C `tp_execute_file` does the same for a NULL `args_json`).
/// Empty keys are dropped: a `ParamEntry` with a blank key is a config artifact
/// and would produce invalid JSON as an object member.
String argsJsonFromParams(List<ParamEntry> params) {
  final Map<String, String> map = <String, String>{
    for (final ParamEntry p in params)
      if (p.key.trim().isNotEmpty) p.key: p.value,
  };
  if (map.isEmpty) return '';
  return jsonEncode(map);
}
