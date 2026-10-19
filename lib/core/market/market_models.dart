// The plugin-market data model: one installable script.
//
// Mirrors `MarketScript` in `src/market_dialog.c:44-50` field-for-field, and
// reproduces the two ways the C code produces entries:
//
//   * from `manifest.json`   — `mkt_fetch_scripts`, market_dialog.c:92-123
//   * from the GitHub API    — the fallback, market_dialog.c:126-152
//
// Field widths are the C ones (`char name[128]`, `file[256]`, `description[256]`,
// `author[64]`, `version[32]`) because those bounds are what the C reader
// enforces with `strncpy`, and a manifest that overflows them is silently
// truncated today. We keep the limits as documentation and validation bounds
// rather than truncating: truncation is data loss and the UI can simply refuse
// an absurd entry.
//
// Pure Dart. No Flutter, no `dart:io`. This file must stay importable from a
// plain `dart test` run.

/// `MKT_MAX_SCRIPTS` (`market_dialog.c:13`).
///
/// The C list stops filling at 64 entries. Kept so the Dart side refuses to
/// build a list the old UI would have silently truncated.
const int kMaxMarketScripts = 64;

/// The field limits from the C `MarketScript` struct.
class MarketFieldLimits {
  const MarketFieldLimits._();
  static const int name = 128;
  static const int file = 256;
  static const int description = 256;
  static const int author = 64;
  static const int version = 32;
}

/// One installable script from a market source.
class MarketScript {
  const MarketScript({
    required this.name,
    required this.file,
    this.description = '',
    this.author = '',
    this.version = '',
    this.sourceRepo = '',
  });

  /// Display name. From the manifest's `name`; the API fallback uses the
  /// filename instead.
  final String name;

  /// The `.lua` filename inside the repo, and the name it is written under in
  /// `scripts/`. Never empty for a usable entry — the C code drops entries
  /// whose `file` is empty (`market_dialog.c:114`).
  final String file;

  /// Manifest `description`. Empty for API-fallback entries (the C code never
  /// sets it there).
  final String description;

  /// Manifest `author`; for API-fallback entries the C code stores the
  /// `user/repo` string (`strcpy(ms->author, repo8)`, line 146).
  final String author;

  /// Manifest `version`. Empty for API-fallback entries.
  final String version;

  /// Which source this came from, as `user/repo`. The C code keeps this in the
  /// dialog state rather than on the entry; carrying it on the model makes
  /// "install this one" a self-contained operation.
  final String sourceRepo;

  /// Whether this entry carries a real description, i.e. whether it came from a
  /// manifest rather than the API listing.
  bool get hasManifestMetadata => description.isNotEmpty || version.isNotEmpty;

  /// Case-insensitive search over name + description.
  ///
  /// This is the market's search predicate (Phase 10 acceptance criterion:
  /// "搜索按 name+description 过滤"). Author and version are deliberately not
  /// searched: the old UI had no search at all, and matching on `author` would
  /// make every entry from the default source match a query containing `bestK`.
  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }

  /// Whether the entry is usable: it must name a `.lua` file.
  bool get isUsable =>
      file.isNotEmpty && file.toLowerCase().endsWith('.lua');

  MarketScript copyWith({
    String? name,
    String? file,
    String? description,
    String? author,
    String? version,
    String? sourceRepo,
  }) =>
      MarketScript(
        name: name ?? this.name,
        file: file ?? this.file,
        description: description ?? this.description,
        author: author ?? this.author,
        version: version ?? this.version,
        sourceRepo: sourceRepo ?? this.sourceRepo,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'file': file,
        'description': description,
        'author': author,
        'version': version,
        'sourceRepo': sourceRepo,
      };

  factory MarketScript.fromJson(Map<String, dynamic> json) => MarketScript(
        name: _string(json['name']),
        file: _string(json['file']),
        description: _string(json['description']),
        author: _string(json['author']),
        version: _string(json['version']),
        sourceRepo: _string(json['sourceRepo']),
      );

  @override
  String toString() => 'MarketScript($name, $file, from $sourceRepo)';

  @override
  bool operator ==(Object other) =>
      other is MarketScript &&
      other.name == name &&
      other.file == file &&
      other.description == description &&
      other.author == author &&
      other.version == version &&
      other.sourceRepo == sourceRepo;

  @override
  int get hashCode =>
      Object.hash(name, file, description, author, version, sourceRepo);
}

/// A non-string JSON value reads as empty, matching `lib/config.c`'s typed
/// readers and the C market's `f->str_val` guard (`market_dialog.c:107`).
String _string(dynamic v) => v is String ? v : '';
