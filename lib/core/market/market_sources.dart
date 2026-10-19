// Source-list management: add, remove, and the 8-source cap.
//
// Ports the `MKT_ID_ADDSRC` / `MKT_ID_DELSRC` handlers from
// `src/market_dialog.c:246-286`:
//
//   * Adding when `source_count >= CFG_MAX_SOURCES` shows
//     `market.max_sources` ("最多支持 8 个源") and does nothing.
//   * An empty input shows `market.enter_repo`
//     ("请在下拉框中输入仓库地址\n格式: user/repo") and does nothing.
//   * A duplicate is detected with `lstrcmpiW` — CASE-INSENSITIVE — and is
//     silently ignored (no message; the source simply does not get added twice).
//   * Removing shifts the rest down and saves.
//
// The functions here return a result enum rather than showing message boxes, so
// the caller decides presentation and this file stays pure logic.
//
// Pure Dart. No Flutter, no `dart:io`.

import '../config/config_schema.dart';

/// The outcome of [addSource].
enum SourceAddResult {
  /// The source was appended.
  added,

  /// An equal (case-insensitive) source is already in the list. Nothing changed.
  duplicate,

  /// The list is already at [ConfigLimits.maxSources]. Nothing changed.
  limitReached,

  /// The input was blank. Nothing changed.
  empty,

  /// The input is not of the form `user/repo`. Nothing changed.
  invalidFormat,
}

/// Validates a source string as `user/repo`.
///
/// The C code accepts anything non-empty and only documents the format in the
/// error message, so a typo produces a source that always fails to fetch. We
/// reject it up front; the message the user sees is the same one that already
/// names the format.
///
/// Accepted: letters, digits, `_`, `-`, `.` on both sides, exactly one `/`.
/// GitHub also allows `.` and `-` in both segments, which this covers.
bool isValidSourceFormat(String input) {
  final String s = input.trim();
  if (s.isEmpty) return false;
  final List<String> parts = s.split('/');
  if (parts.length != 2) return false;
  final RegExp segment = RegExp(r'^[A-Za-z0-9._-]+$');
  return segment.hasMatch(parts[0]) && segment.hasMatch(parts[1]);
}

/// Appends [input] to [sources] when it is valid, new, and there is room.
///
/// [sources] is mutated in place on success, matching `g_cfg.sources`. The
/// caller is responsible for saving the config afterwards.
SourceAddResult addSource(List<String> sources, String input) {
  final String value = input.trim();

  if (value.isEmpty) return SourceAddResult.empty;

  // The cap is checked BEFORE the format, matching the C order: a user at the
  // limit gets told about the limit rather than about their typo.
  if (sources.length >= ConfigLimits.maxSources) return SourceAddResult.limitReached;

  if (!isValidSourceFormat(value)) return SourceAddResult.invalidFormat;

  // `lstrcmpiW`: case-insensitive, and the stored spelling is kept as typed.
  for (final String existing in sources) {
    if (existing.toLowerCase() == value.toLowerCase()) {
      return SourceAddResult.duplicate;
    }
  }

  sources.add(value);
  return SourceAddResult.added;
}

/// Removes the source at [index], shifting the rest down.
///
/// Returns true when something was removed. An out-of-range index is a no-op,
/// matching the C guard `if (idx < 0 || idx >= g_cfg.source_count) break;`.
bool removeSourceAt(List<String> sources, int index) {
  if (index < 0 || index >= sources.length) return false;
  sources.removeAt(index);
  return true;
}

/// Whether another source can be added.
bool canAddSource(List<String> sources) => sources.length < ConfigLimits.maxSources;

/// The number of sources that may still be added.
int remainingSourceSlots(List<String> sources) {
  final int remaining = ConfigLimits.maxSources - sources.length;
  return remaining < 0 ? 0 : remaining;
}
