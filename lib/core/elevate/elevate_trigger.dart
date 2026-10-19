// When does a script need administrator privileges?
//
// ─────────────────────────────────────────────────────────────────────────────
// INVESTIGATION: there is no existing convention to port
// ─────────────────────────────────────────────────────────────────────────────
// The original elevate implementation is gone (see elevate_service.dart), so
// the trigger had to be reconstructed. Before inventing anything, the following
// were searched for any elevate-adjacent convention:
//
//   docs/LUA_API.md          no match for admin|elevate|提权|管理员|root|sudo|privileg
//   docs/LUA_API_EN.md       only an unrelated "Root directory to search"
//   examples/*.lua headers   the only directives present are @param, @refresh
//   scripts/*.lua headers    the only directives present are @param, @refresh,
//                            @bar_width, @name, @realtime
//   src/ lib/*.c             no elevate/runas/IsUserAnAdmin reference at all
//   lang/*.json              only the four elevate.* strings, no directive name
//
// Nothing. So the directive below is a GUESS, isolated behind a single constant
// so it can be changed in one place once the real convention is confirmed.
//
// What the search DID establish is that the header is already an extension point
// with informal directives the C parser ignores: `-- @bar_width 120` appears in
// several shipped scripts and `-- @realtime` in `scripts/dino_runner.lua`, and
// neither `script_parse_params` nor `script_parse_refresh` knows about them. A
// `@admin` directive is therefore consistent with existing practice even though
// no script currently uses one.
//
// Pure Dart (`dart:io` for file reads only).

import 'dart:io';

import '../market/script_header.dart';

/// The header directive that declares "this script needs admin".
///
/// ⚠️ RECONSTRUCTED, NOT PORTED. See the file header. If the real convention
/// differs, changing this one constant is the whole fix.
const String kAdminDirective = '@admin';

/// Accepted aliases for [kAdminDirective].
///
/// Kept deliberately short. Every alias is a guess, so the surface stays small
/// and the primary spelling is the documented one.
const List<String> kAdminDirectiveAliases = <String>[
  '@admin',
  '@require_admin',
  '@elevate',
];

/// Why a script is considered to need elevation.
enum ElevateTrigger {
  /// No admin directive found. The normal case.
  none,

  /// A `@admin`-family directive is present in the header.
  declared,
}

/// Whether [source] declares that it needs administrator privileges.
///
/// Scans only the leading `--` comment block, the same region
/// `parseScriptParams` reads, so a `-- @admin` mentioned inside a function body
/// does not count.
bool scriptDeclaresAdmin(String source) =>
    findAdminDirective(source) != null;

/// The directive that triggered, or `null` when there is none.
///
/// Returning the matched spelling (rather than a bool) lets the UI show which
/// declaration asked for elevation, which is the difference between "something
/// wants admin" and "this script wants admin".
String? findAdminDirective(String source) {
  // Reuse the header scanner's stopping rule (leading comments only) rather
  // than reimplementing it: if the two ever diverge, the params parser and this
  // would disagree about where the header ends.
  final List<String> headerLines = headerCommentLines(source);
  for (final String line in headerLines) {
    final String p = line.trimLeft();
    for (final String alias in kAdminDirectiveAliases) {
      if (_matchesDirective(p, alias)) return alias;
    }
  }
  return null;
}

/// Whether a script needs admin, given its source and whether we are elevated.
///
/// The bar shows `elevate.blocked` exactly when this is true.
bool isElevationBlocked({
  required String source,
  required bool isElevated,
}) =>
    !isElevated && scriptDeclaresAdmin(source);

/// Reads a script and decides whether it is elevation-blocked.
Future<bool> isElevationBlockedForFile(
  String path, {
  required bool isElevated,
}) async {
  final String source = await readScriptSource(path);
  return isElevationBlocked(source: source, isElevated: isElevated);
}

/// Reads a script as UTF-8, returning `''` when it cannot be read.
Future<String> readScriptSource(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return '';
    return await file.readAsString();
  } catch (_) {
    return '';
  }
}

/// True when [line] (already `--`-stripped) starts with [directive] as a whole
/// token, so `@administrator` does not match `@admin`.
bool _matchesDirective(String line, String directive) {
  if (!line.startsWith(directive)) return false;
  if (line.length == directive.length) return true;
  final int next = line.codeUnitAt(directive.length);
  // Whitespace or end-of-line terminates the directive.
  return next == 0x20 || next == 0x09 || next == 0x0D || next == 0x0A;
}
