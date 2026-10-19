// Config migration: legacy Windows JSON, legacy Windows INI, and the macOS
// Swift schema, all unified onto the Windows schema.
//
// Sources of truth for each target shape:
//   * `lib/config.h` / `lib/config.c`   — the unified (Windows) schema
//   * `src/macos/Models/AppConfig.swift`
//     `src/macos/Models/PinItem.swift`  — the legacy Swift schema
//   * `lib/config.c:config_load_ini`    — the pre-JSON INI schema
//
// The unified schema deliberately stays at version 1 so the on-disk file
// remains byte-compatible with `lib/config.c`. "Old Windows schema" therefore
// means *structurally* old — a version-1 document that predates `sources`,
// `bar_x`/`bar_y`, `bar_bg_color` and `dlg_*` — not a different version number.
// A file declaring version > 1 is refused outright (see ConfigVersionError).

import 'dart:convert';
import 'dart:io';

import 'config_repository.dart';
import 'config_schema.dart';

/// Which legacy format a document came from.
enum ConfigOrigin {
  /// Already the unified schema; nothing to do.
  unified,

  /// A version-1 Windows JSON document missing the newer field set.
  windowsV1Json,

  /// The pre-JSON `config.ini` (`lib/config.c:config_load_ini`).
  windowsIni,

  /// The macOS Swift `Codable` schema (UUID `id`, camelCase, no bar/dlg fields).
  macosSwift,
}

/// What a migration pass did.
sealed class MigrationOutcome {
  const MigrationOutcome();
}

/// The file was already unified.
class AlreadyUnified extends MigrationOutcome {
  const AlreadyUnified(this.path);
  final String path;
}

/// The file was converted in place, with the original preserved.
class Migrated extends MigrationOutcome {
  const Migrated({
    required this.path,
    required this.from,
    required this.backupPath,
    required this.wroteConfig,
  });

  final String path;
  final ConfigOrigin from;

  /// Where the untouched original was preserved. Null when a backup already
  /// existed and was deliberately left alone (never clobber the first copy).
  final String? backupPath;

  /// False when the migrated config was returned but not written to disk.
  final bool wroteConfig;
}

/// Detects which format a decoded document is in.
///
/// Structural, not version-based: the Swift schema has no `global` object and
/// uses a UUID `id` per item, which no Windows document ever has.
ConfigOrigin detectConfigOrigin(Map<String, dynamic> json) {
  final hasGlobal = json['global'] is Map;
  final items = json['items'];
  final itemList = items is List ? items : const <dynamic>[];

  if (!hasGlobal) {
    // Swift AppConfig has no `global`; it hoists fontSize/fontColor/bgColor to
    // the root. Fall back to the per-item UUID marker for a bare items-only
    // document.
    final swiftRoot = json.containsKey('fontSize') ||
        json.containsKey('fontColor') ||
        json.containsKey('bgColor') ||
        json.containsKey('scrollEnabled');
    final swiftItem = itemList.any((e) => e is Map && _looksLikeUuid(e['id']));
    if (swiftRoot || swiftItem) return ConfigOrigin.macosSwift;

    // No `global` and no Swift markers: treat as an old Windows document and
    // let the field defaults fill it in.
    return ConfigOrigin.windowsV1Json;
  }

  // Windows-shaped. Is it missing any field the unified schema added?
  final global = (json['global'] as Map).cast<String, dynamic>();
  final missingSources = !json.containsKey('sources');
  final missingGlobal = !global.containsKey('scroll_enabled');
  final missingItemFields = itemList.any((e) {
    if (e is! Map) return false;
    final item = e.cast<String, dynamic>();
    return !item.containsKey('bar_x') ||
        !item.containsKey('bar_bg_color') ||
        !item.containsKey('dlg_x');
  });

  if (missingSources || missingGlobal || missingItemFields) {
    return ConfigOrigin.windowsV1Json;
  }
  return ConfigOrigin.unified;
}

/// Converts a decoded document to the unified model.
///
/// [origin] should come from [detectConfigOrigin]; pass
/// [ConfigOrigin.unified] to get a straight [TaskPinConfig.fromJson].
TaskPinConfig migrateConfig(
  Map<String, dynamic> json, {
  required ConfigOrigin origin,
  String path = '<memory>',
}) {
  switch (origin) {
    case ConfigOrigin.unified:
      return TaskPinConfig.fromJson(json, path: path);
    case ConfigOrigin.windowsV1Json:
      return _migrateWindowsV1(json);
    case ConfigOrigin.macosSwift:
      return _migrateMacOsSwift(json);
    case ConfigOrigin.windowsIni:
      throw ArgumentError.value(
        origin,
        'origin',
        'INI documents are not JSON; use ConfigMigrator to migrate a '
            'config.ini, which owns the INI parser.',
      );
  }
}

// ---------------------------------------------------------------------------
// (a) Windows version-1 JSON -> unified
// ---------------------------------------------------------------------------

/// Fills in the fields the unified schema added, leaving everything else —
/// including unknown keys — exactly as found.
///
/// Item fields the real files already carry (`bar_width`, `dlg_*`) are left to
/// `PinItem.fromJson`, whose defaults are the same C defaults.
TaskPinConfig _migrateWindowsV1(Map<String, dynamic> json) {
  final global = json['global'] is Map
      ? (json['global'] as Map).cast<String, dynamic>()
      : <String, dynamic>{};

  final items = (json['items'] is List ? json['items'] as List : const [])
      .map((e) => PinItem.fromJson(
            e is Map ? e.cast<String, dynamic>() : <String, dynamic>{},
          ))
      .toList(growable: true);

  final sources = (json['sources'] is List ? json['sources'] as List : const [])
      .whereType<String>()
      .toList(growable: true);

  return TaskPinConfig(
    version: kUnifiedConfigVersion,
    items: items,
    width: _asInt(global['width'], 320),
    posX: _asInt(global['pos_x'], -1),
    posY: _asInt(global['pos_y'], -1),
    fontSize: _asInt(global['font_size'], 9),
    fontColor: _asString(global['font_color'], 'FFFFFF'),
    bgColor: _asString(global['bg_color'], 'FFFFFFFF'),
    scrollEnabled: _asBool(global['scroll_enabled'], true),
    logLevel: _asInt(global['log_level'], 0),
    // `config.c:166-169` injects the default when the list is empty, so the
    // same happens here; an old file with no `sources` ends up with one.
    sources: sources.isEmpty ? <String>['bestK/taskpin-plugins'] : sources,
    globalExtra: _unknownOf(global, TaskPinConfig.knownGlobalKeys),
    extra: _unknownOf(json, TaskPinConfig.knownRootKeys),
  );
}

// ---------------------------------------------------------------------------
// (b) macOS Swift schema -> unified
// ---------------------------------------------------------------------------

/// `src/macos/Models/AppConfig.swift` + `PinItem.swift`.
///
/// Key differences handled here:
///   * `type` is the string enum `"url"`/`"lua"` -> 0/1
///   * camelCase keys -> snake_case
///   * a UUID `id` per item and per param, plus `paramType`, which the unified
///     schema has no home for -> dropped
///   * `bar_width`/`bar_x`/`bar_y`/`bar_bg_color`/`dlg_*` -> absent, so they
///     take the unified defaults
///   * `fontSize`/`fontColor`/`bgColor`/`scrollEnabled` live at the root
///   * `global.width`/`pos_x`/`pos_y`/`log_level` -> absent, take C defaults
///   * colors are RGB; the unified format is COLORREF (BGR). See [_macRgbHex].
TaskPinConfig _migrateMacOsSwift(Map<String, dynamic> json) {
  final items = (json['items'] is List ? json['items'] as List : const [])
      .whereType<Map>()
      .map((e) => _migrateMacItem(e.cast<String, dynamic>()))
      .toList(growable: true);

  final sources = (json['sources'] is List ? json['sources'] as List : const [])
      .whereType<String>()
      .toList(growable: true);

  return TaskPinConfig(
    version: kUnifiedConfigVersion,
    items: items,
    // Not present in the Swift schema; C defaults.
    width: 320,
    posX: -1,
    posY: -1,
    fontSize: _asInt(json['fontSize'], 12),
    fontColor: _macRgbHex(json['fontColor'], 'FFFFFF', withAlpha: false),
    bgColor: _macRgbHex(json['bgColor'], '1E1E1E', withAlpha: true),
    scrollEnabled: _asBool(json['scrollEnabled'], true),
    logLevel: 0,
    sources: sources.isEmpty ? <String>['bestK/taskpin-plugins'] : sources,
    globalExtra: _unknownOf(json, const <String>{
      'items',
      'fontSize',
      'fontColor',
      'bgColor',
      'scrollEnabled',
      'sources',
    }),
  );
}

PinItem _migrateMacItem(Map<String, dynamic> json) {
  final params = (json['params'] is List ? json['params'] as List : const [])
      .whereType<Map>()
      .map((e) {
    final p = e.cast<String, dynamic>();
    return ParamEntry(
      key: _asString(p['key'], ''),
      value: _asString(p['value'], ''),
      label: _asString(p['label'], ''),
      // `id` (UUID) and `paramType` have no unified equivalent.
      extra: _unknownOf(p, const <String>{'id', 'key', 'value', 'label', 'paramType'}),
    );
  }).toList(growable: true);

  return PinItem(
    type: _macType(json['type']),
    name: _asString(json['name'], 'Untitled'),
    intervalMs: _asInt(json['intervalMs'], 5000),
    url: _asString(json['url'], ''),
    reqHeaders: _asString(json['reqHeaders'], ''),
    fieldExpr: _asString(json['fieldExpr'], ''),
    clickEnabled: _asBool(json['clickEnabled'], false),
    clickUrl: _asString(json['clickUrl'], ''),
    luaPath: _asString(json['luaPath'], ''),
    params: params,
    pinned: _asBool(json['pinned'], false),
    // Everything below is absent from the Swift schema and takes the unified
    // default, which is what PinItem's constructor already supplies.
    extra: _unknownOf(json, const <String>{
      'id',
      'type',
      'name',
      'intervalMs',
      'url',
      'reqHeaders',
      'fieldExpr',
      'clickEnabled',
      'clickUrl',
      'luaPath',
      'params',
      'pinned',
    }),
  );
}

int _macType(dynamic v) {
  if (v is String) {
    final lower = v.toLowerCase();
    if (lower == 'lua') return PinItemType.lua;
    if (lower == 'url') return PinItemType.url;
  }
  if (v is int) return v;
  return PinItemType.lua; // Swift default: `var type: PinItemType = .lua`
}

/// Converts a macOS RGB hex string to the unified COLORREF hex encoding.
///
/// **This assumes the macOS values are RGB** (the AppKit/`NSColor` convention),
/// while the unified format stores a Win32 COLORREF, i.e. `0x00BBGGRR`. The two
/// defaults that appear in the real Swift source (`"FFFFFF"` and `"1E1E1E"`)
/// are byte-symmetric, so no live file can confirm or refute the assumption —
/// hence this is one function, with a test using an asymmetric color, so a
/// wrong guess fails loudly instead of silently swapping red and blue.
///
/// [withAlpha] selects the 8-digit form used by `bg_color`; the 6-digit form is
/// used by `font_color`, matching `json_add_color`'s two call sites.
String _macRgbHex(dynamic raw, String fallback, {required bool withAlpha}) {
  final text = raw is String ? raw.trim() : '';
  final digits = text.startsWith('#') ? text.substring(1) : text;
  if (digits.length != 6) {
    // Fall back to the symmetric default, converting it the same way so the
    // output encoding is still consistent.
    return withAlpha ? '00$fallback' : fallback;
  }
  final value = int.tryParse(digits, radix: 16);
  if (value == null) {
    return withAlpha ? '00$fallback' : fallback;
  }
  final r = (value >> 16) & 0xFF;
  final g = (value >> 8) & 0xFF;
  final b = value & 0xFF;
  final colorref = (b << 16) | (g << 8) | r;
  return withAlpha ? ConfigColor.format8(colorref) : ConfigColor.format6(colorref);
}

// ---------------------------------------------------------------------------
// (c) Windows config.ini -> unified
// ---------------------------------------------------------------------------

/// Parses the `GetPrivateProfileStringW` format that `config_load_ini` reads.
///
/// The files written by the C layer are UTF-16LE with a BOM, so that is handled
/// first; UTF-8 is accepted as a fallback for hand-edited files.
class IniDocument {
  IniDocument._(this._sections);

  final Map<String, Map<String, String>> _sections;

  static IniDocument parse(List<int> bytes) {
    final text = _decodeIni(bytes);
    final sections = <String, Map<String, String>>{};
    var current = sections.putIfAbsent('', () => <String, String>{});
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith(';') || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        final name = line.substring(1, line.length - 1).trim();
        current = sections.putIfAbsent(name, () => <String, String>{});
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      current[key] = value;
    }
    return IniDocument._(sections);
  }

  static String _decodeIni(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16LE with BOM. `GetPrivateProfileStringW` writes exactly this.
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String getString(String section, String key, String fallback) =>
      _sections[section]?[key] ?? fallback;

  int getInt(String section, String key, int fallback) {
    final raw = _sections[section]?[key];
    if (raw == null || raw.isEmpty) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  /// The INI stores these as base64 because `GetPrivateProfileString` cannot
  /// carry newlines or non-ASCII reliably.
  String getBase64(String section, String key) {
    final raw = _sections[section]?[key];
    if (raw == null || raw.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(raw), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}

/// `lib/config.c:config_load_ini`, including the legacy `selected` fallback.
TaskPinConfig migrateIni(IniDocument ini) {
  const global = 'Global';
  final count = _clamp(ini.getInt(global, 'count', 0), 0, ConfigLimits.maxItems);

  final items = <PinItem>[];
  for (var i = 0; i < count; i++) {
    final section = 'Item_$i';
    final paramCount =
        _clamp(ini.getInt(section, 'param_count', 0), 0, ConfigLimits.maxParams);
    final params = <ParamEntry>[];
    for (var j = 0; j < paramCount; j++) {
      params.add(ParamEntry(
        key: ini.getString(section, 'param_key_$j', ''),
        value: ini.getString(section, 'param_val_$j', ''),
        label: ini.getString(section, 'param_lbl_$j', ''),
      ));
    }

    items.add(PinItem(
      type: ini.getInt(section, 'type', PinItemType.url),
      name: ini.getString(section, 'name', 'Untitled'),
      intervalMs: ini.getInt(section, 'interval_ms', 5000),
      url: ini.getString(section, 'url', 'http://localhost:8080/status'),
      reqHeaders: ini.getBase64(section, 'req_headers_b64'),
      fieldExpr: ini.getBase64(section, 'field_expr_b64'),
      clickEnabled: ini.getInt(section, 'click_enabled', 0) != 0,
      clickUrl: ini.getString(section, 'click_url', ''),
      luaPath: ini.getString(section, 'lua_path', ''),
      params: params,
      pinned: ini.getInt(section, 'pinned', 0) != 0,
      barWidth: ini.getInt(section, 'bar_width', 0),
      barX: ini.getInt(section, 'bar_x', -1),
      barY: ini.getInt(section, 'bar_y', -1),
      barBgColor:
          _iniColor(ini.getString(section, 'bar_bg_color', 'FFFFFFFF'), width: 8),
      dlgX: ini.getInt(section, 'dlg_x', -1),
      dlgY: ini.getInt(section, 'dlg_y', -1),
      dlgW: ini.getInt(section, 'dlg_w', 0),
      dlgH: ini.getInt(section, 'dlg_h', 0),
    ));
  }

  // `config.c:282-292`: when nothing is pinned, the legacy single-selection
  // index becomes the pinned item.
  if (!items.any((it) => it.pinned)) {
    final legacy = ini.getInt(global, 'selected', -1);
    if (legacy >= 0 && legacy < items.length) {
      items[legacy].pinned = true;
    }
  }

  final sourceCount =
      _clamp(ini.getInt('Sources', 'count', 0), 0, ConfigLimits.maxSources);
  final sources = <String>[];
  for (var i = 0; i < sourceCount; i++) {
    final value = ini.getString('Sources', 'source_$i', '');
    if (value.isNotEmpty) sources.add(value);
  }

  return TaskPinConfig(
    version: kUnifiedConfigVersion,
    items: items,
    width: ini.getInt(global, 'width', 320),
    posX: ini.getInt(global, 'pos_x', -1),
    posY: ini.getInt(global, 'pos_y', -1),
    fontSize: ini.getInt(global, 'font_size', 9),
    fontColor: _iniColor(ini.getString(global, 'font_color', 'FFFFFF'), width: 6),
    bgColor: _iniColor(ini.getString(global, 'bg_color', 'FFFFFFFF'), width: 8),
    scrollEnabled: ini.getInt(global, 'scroll_enabled', 1) != 0,
    logLevel: ini.getInt(global, 'log_level', 0),
    sources: sources.isEmpty ? <String>['bestK/taskpin-plugins'] : sources,
  );
}

/// Normalises an INI color the way `wcstoul(s, NULL, 16)` does: parse, then
/// re-emit in the canonical width. Keeps `font_color` at 6 digits and the
/// others at 8, so a migrated file matches what the C writer would have
/// produced.
String _iniColor(String raw, {required int width}) {
  final value = ConfigColor.tryParse(raw);
  if (value == null) return width == 6 ? 'FFFFFF' : kColorUseGlobal;
  return width == 6 ? ConfigColor.format6(value) : ConfigColor.format8(value);
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

/// Detects and migrates a legacy config file in place.
///
/// Ordering mirrors `config_load`: JSON first, INI second.
class ConfigMigrator {
  ConfigMigrator({required this.paths});

  final ConfigPaths paths;

  /// Migrates the config at [paths.configFile] when it is in a legacy format.
  ///
  /// Returns [AlreadyUnified] when nothing needed doing. Throws
  /// [ConfigVersionError] for a future version, leaving the file untouched.
  Future<MigrationOutcome> migrateIfNeeded() async {
    final configFile = File(paths.configFile);

    if (!configFile.existsSync()) {
      final iniFile = File(paths.legacyIniFile);
      if (iniFile.existsSync()) {
        return _migrateIniFile(iniFile);
      }
      return AlreadyUnified(paths.configFile);
    }

    final text = await configFile.readAsString(encoding: utf8);
    if (text.trim().isEmpty) return AlreadyUnified(paths.configFile);

    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw ConfigFormatError(paths.configFile, 'not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw ConfigFormatError(
        paths.configFile,
        'expected a JSON object at the root, got ${decoded.runtimeType}',
      );
    }
    final json = decoded.cast<String, dynamic>();

    // Refuse a newer format BEFORE any backup or rewrite.
    final version = json['version'];
    if (version is int && version > kUnifiedConfigVersion) {
      throw ConfigVersionError(version: version, path: paths.configFile);
    }

    final origin = detectConfigOrigin(json);
    if (origin == ConfigOrigin.unified) {
      return AlreadyUnified(paths.configFile);
    }

    final migrated = migrateConfig(json, origin: origin, path: paths.configFile);
    final backup = _backup(paths.legacyJsonBackup, configFile);
    await _write(migrated);

    return Migrated(
      path: paths.configFile,
      from: origin,
      backupPath: backup,
      wroteConfig: true,
    );
  }

  Future<MigrationOutcome> _migrateIniFile(File iniFile) async {
    final ini = IniDocument.parse(await iniFile.readAsBytes());
    final migrated = migrateIni(ini);

    // Match `config.c:352-355`: the INI becomes `config.ini.bak`.
    final backup = _backup('${iniFile.path}.bak', iniFile);
    await _write(migrated);

    return Migrated(
      path: paths.configFile,
      from: ConfigOrigin.windowsIni,
      backupPath: backup,
      wroteConfig: true,
    );
  }

  /// Copies [source] to [backupPath] unless a backup already exists.
  ///
  /// Never clobbers: the first backup is the truest original, and a second
  /// migration pass must not overwrite it with already-converted content.
  String? _backup(String backupPath, File source) {
    final backup = File(backupPath);
    if (backup.existsSync()) return null;
    backup.parent.createSync(recursive: true);
    source.copySync(backupPath);
    return backupPath;
  }

  Future<void> _write(TaskPinConfig cfg) async {
    final target = File(paths.configFile);
    target.parent.createSync(recursive: true);
    final tmp = File('${paths.configFile}.tmp');
    await tmp.writeAsString(cfg.toJsonString(), encoding: utf8, flush: true);
    try {
      await tmp.rename(paths.configFile);
    } on FileSystemException {
      if (target.existsSync()) await target.delete();
      await tmp.rename(paths.configFile);
    }
  }
}

// ---------------------------------------------------------------------------
// Small coercion helpers (mirrors of config.c's typed readers)
// ---------------------------------------------------------------------------

String _asString(dynamic v, String fallback) => v is String ? v : fallback;
bool _asBool(dynamic v, bool fallback) => v is bool ? v : fallback;

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return fallback;
}

/// `num.clamp` returns `num`, which would need a cast at every call site; this
/// keeps the int type through the clamp.
int _clamp(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

Map<String, dynamic> _unknownOf(Map<String, dynamic> json, Set<String> known) {
  final out = <String, dynamic>{};
  for (final entry in json.entries) {
    if (!known.contains(entry.key)) out[entry.key] = entry.value;
  }
  return out;
}

final RegExp _uuidPattern =
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

bool _looksLikeUuid(dynamic v) => v is String && _uuidPattern.hasMatch(v);
