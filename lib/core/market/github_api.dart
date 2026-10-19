// The GitHub contents-API fallback listing.
//
// Ports the fallback branch of `mkt_fetch_scripts` (`src/market_dialog.c:126-152`):
// when a repo has no `manifest.json`, list the repo root through
// `https://api.github.com/repos/<user>/<repo>/contents/` and keep the `.lua`
// entries.
//
// The C reader's rules, reproduced here:
//
//   * The body must be a JSON ARRAY. A 404 from the API comes back as an object
//     (`{"message": "Not Found"}`), which yields an empty list — not an error.
//     `src/market_dialog.c:131` guards with `root->type == JSON_ARRAY`.
//   * Only `name` is read from each entry.
//   * A name is kept when it ends in `.lua` AND is at least 5 characters, i.e.
//     `len < 5 || strcmp(name + len - 4, ".lua") != 0` (line 140). The length
//     guard rejects a bare `.lua` with no stem.
//   * The listing is not recursive. Subdirectories appear as entries with
//     `type == "dir"` and are skipped naturally, because a directory name does
//     not end in `.lua` — the C code does not check `type` either.
//   * `author` is set to the `user/repo` string, and `name` is set to the
//     filename (there is no manifest metadata to use).
//
// Pure Dart (`dart:convert` only).

import 'dart:convert';

import 'market_models.dart';

/// The suffix an entry must carry to be considered a script.
const String kLuaExtension = '.lua';

/// Parses a contents-API listing body into scripts.
///
/// Returns an empty list for anything that is not a JSON array — including the
/// API's own error objects. The caller cannot distinguish "no scripts" from
/// "repo not found" here, which matches the old UI's behaviour (it showed
/// "共 0 个脚本" in both cases).
List<MarketScript> parseContentsListing(String body, {String sourceRepo = ''}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return <MarketScript>[];
  }
  if (decoded is! List) return <MarketScript>[];

  final List<MarketScript> out = <MarketScript>[];
  for (final dynamic raw in decoded) {
    if (out.length >= kMaxMarketScripts) break;
    if (raw is! Map) continue;

    final String name = _string(raw['name']);
    if (!isLuaFileName(name)) continue;

    out.add(
      MarketScript(
        name: name,
        file: name,
        // The C code sets author to the repo string and leaves description and
        // version empty for API-listed entries.
        author: sourceRepo,
        sourceRepo: sourceRepo,
      ),
    );
  }
  return out;
}

/// True when [name] is a `.lua` filename with a non-empty stem.
///
/// Mirrors `len < 5 || strcmp(name + len - 4, ".lua") != 0`: `.lua` alone is 4
/// characters and is rejected; `a.lua` is 5 and is accepted. The comparison is
/// case-insensitive here because the C `strcmp` is byte-exact but a repo
/// containing `Foo.LUA` would otherwise be invisible to the market — a
/// deliberate, documented divergence.
bool isLuaFileName(String name) {
  if (name.length < 5) return false;
  return name.toLowerCase().endsWith(kLuaExtension);
}

String _string(dynamic v) => v is String ? v : '';
