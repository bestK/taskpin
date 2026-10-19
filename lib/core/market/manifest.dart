// The `manifest.json` parser.
//
// Ports `mkt_fetch_scripts`'s manifest branch (`src/market_dialog.c:92-123`)
// exactly, including its tolerance rules:
//
//   * The document is only a manifest if it has a `scripts` ARRAY. Anything
//     else (no `scripts` key, `scripts` not an array, a body that is not JSON at
//     all) makes the caller fall through to the GitHub contents API. That
//     fall-through is why [parseManifest] returns `null` rather than an empty
//     list: `null` means "not a manifest", `[]` means "a manifest with no
//     scripts".
//   * A field is only read when it is a string (`if (!f->key || !f->str_val)
//     continue;`, line 107). A number or object is ignored, leaving the default.
//   * An entry with an empty `file` is DROPPED (`if (ms->file[0])
//     s_mkt->script_count++`, line 114). Such an entry cannot be installed, so
//     keeping it would only produce a button that fails.
//   * The list is capped at [kMaxMarketScripts].
//
// Pure Dart (`dart:convert` only).

import 'dart:convert';

import 'market_models.dart';

/// The manifest filename requested from the repo root.
const String kManifestFileName = 'manifest.json';

/// Parses a `manifest.json` body.
///
/// Returns `null` when [body] is not a manifest (not JSON, not an object, or no
/// `scripts` array) so the caller can fall back to the contents API. Returns a
/// list — possibly empty — when it is one.
///
/// [sourceRepo] is stamped onto every entry so an install knows where the file
/// came from.
List<MarketScript>? parseManifest(String body, {String sourceRepo = ''}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final dynamic scripts = decoded['scripts'];
  if (scripts is! List) return null;

  final List<MarketScript> out = <MarketScript>[];
  for (final dynamic raw in scripts) {
    if (out.length >= kMaxMarketScripts) break;
    if (raw is! Map) continue;

    final String file = _string(raw['file']);
    // A fileless entry is unusable; the C reader skips it too.
    if (file.isEmpty) continue;

    final String name = _string(raw['name']);
    out.add(
      MarketScript(
        // The C code leaves `name` empty when the manifest omits it; the UI
        // falls back to the filename for display. Kept empty here so the model
        // stays a faithful record of the manifest.
        name: name,
        file: file,
        description: _string(raw['description']),
        author: _string(raw['author']),
        version: _string(raw['version']),
        sourceRepo: sourceRepo,
      ),
    );
  }
  return out;
}

/// Whether [body] looks like a manifest at all, without building the list.
///
/// Used by the fetcher to decide manifest-vs-API without allocating. Cheap
/// enough to run on every fetch.
bool isManifestBody(String body) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return false;
  }
  return decoded is Map && decoded['scripts'] is List;
}

String _string(dynamic v) => v is String ? v : '';
