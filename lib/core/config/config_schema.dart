// TaskPin unified configuration model.
//
// Mirrors `lib/config.h` (TaskPinConfig / PinItem / ParamEntry) field-for-field,
// and mirrors `lib/config.c` (config_load_json / config_save) for defaults,
// key order and encoding conventions.
//
// This file is deliberately dependency-free: it imports only `dart:convert`.
// It must stay usable from pure-Dart tests and from the config isolate.
//
// ---------------------------------------------------------------------------
// READ THIS BEFORE CHANGING ANYTHING ABOUT COLORS
// ---------------------------------------------------------------------------
// Colors are stored on disk as hex STRINGS, not as integers, because that is
// the only representation that round-trips `lib/config.c` exactly:
//
//   * `json_read_color`  does `wcstoul(s, NULL, 16)`          (config.c:61-69)
//   * `json_add_color`   does `sprintf("%08X", v)`            (config.c:78-85)
//   * global.font_color  is written with 6 digits (`%06X`, alpha masked)
//   * global.bg_color    is written with 8 digits (`%08X`)
//   * item.bar_bg_color  is written with 8 digits (`%08X`)
//
// The integer is a Win32 COLORREF, i.e. 0x00BBGGRR. Therefore a config hex
// string is byte-order BGR, while a Lua `font("#RRGGBB")` string is byte-order
// RGB (lib/scripting.c:149-160 builds it with RGB(r,g,b)). The SAME literal
// "FF0000" means blue in config and red in a script. See ConfigColor docs.
//
// This layer therefore treats colors as OPAQUE STRINGS. It never normalizes,
// never reorders bytes, and never converts to ARGB implicitly. Any conversion
// goes through the explicitly named helpers at the bottom of this file.
// ---------------------------------------------------------------------------

import 'dart:convert';

/// Limits mirrored from `lib/config.h`.
///
/// The Dart model does NOT truncate to these; truncation is data loss and
/// belongs at the bar/engine boundary. They are exposed so that boundary (and
/// the UI) can validate against the same numbers the C layer enforces.
class ConfigLimits {
  const ConfigLimits._();

  static const int maxUrl = 1024; // CFG_MAX_URL
  static const int maxName = 128; // CFG_MAX_NAME
  static const int maxExpr = 4096; // CFG_MAX_EXPR
  static const int maxPath = 512; // CFG_MAX_PATH
  static const int maxItems = 64; // CFG_MAX_ITEMS
  static const int maxParams = 16; // CFG_MAX_PARAMS
  static const int maxParamKey = 64; // CFG_MAX_PARAM_KEY
  static const int maxParamVal = 2048; // CFG_MAX_PARAM_VAL
  static const int maxSources = 8; // CFG_MAX_SOURCES

  /// NOT in config.h. `src/ui.h:49` defines `MAX_BARS 16`, and
  /// `src/bar_window.c:445` stops creating bars at that count. So a config may
  /// hold up to [maxItems] items but the Windows bar layer can only ever pin
  /// [maxBars] of them. Kept here as a cross-reference for the bar phase.
  static const int maxBars = 16;
}

/// PinItem.type values (`ITEM_TYPE_URL` / `ITEM_TYPE_LUA`).
class PinItemType {
  const PinItemType._();
  static const int url = 0;
  static const int lua = 1;
}

/// The on-disk format version this build reads and writes.
///
/// `lib/config.c:379` writes a hardcoded literal `1` and never reads the field
/// back. The unified schema intentionally stays at 1 so the file remains
/// byte-compatible with the C implementation; "old schema" is detected
/// structurally (missing `sources` / `bar_x` / `bar_bg_color` / `dlg_*`), not
/// by a version bump. See migration.dart.
const int kUnifiedConfigVersion = 1;

/// `bar_bg_color` sentinel meaning "fall back to the global bg color".
///
/// This is an exact string comparison in the C layer:
/// `src/bar_window.c:93` tests `bar_bg_color != 0xFFFFFFFF`. Note this is NOT
/// the color white; it means "unset". A literal white bar would be "FFFFFFFF"
/// only by coincidence of the sentinel, so the UI must never write the
/// sentinel as a user-chosen color.
const String kColorUseGlobal = 'FFFFFFFF';

/// Thrown when a config file declares a format version this build cannot read.
///
/// `load()` refuses rather than silently downgrading, and leaves the file
/// untouched (no backup, no rewrite).
class ConfigVersionError implements Exception {
  const ConfigVersionError({
    required this.version,
    required this.path,
    this.supported = kUnifiedConfigVersion,
  });

  final int version;
  final int supported;
  final String path;

  @override
  String toString() =>
      'ConfigVersionError: $path declares version $version, but this build '
      'only supports version $supported. Refusing to load rather than '
      'silently downgrading. Upgrade TaskPin, or move the file aside.';
}

/// Thrown when a file exists but cannot be interpreted as a config at all.
class ConfigFormatError implements Exception {
  const ConfigFormatError(this.path, this.reason);
  final String path;
  final String reason;

  @override
  String toString() => 'ConfigFormatError: $path: $reason';
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// One `@param` declaration value: `lib/config.h` `ParamEntry`.
class ParamEntry {
  ParamEntry({
    this.key = '',
    this.value = '',
    this.label = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  /// `ParamEntry.key` (CFG_MAX_PARAM_KEY wide chars).
  String key;

  /// `ParamEntry.value` (CFG_MAX_PARAM_VAL wide chars).
  String value;

  /// `ParamEntry.label` (CFG_MAX_NAME wide chars).
  String label;

  /// Unknown keys found on this object, preserved verbatim across a round-trip.
  final Map<String, dynamic> extra;

  static const Set<String> knownKeys = <String>{'key', 'value', 'label'};

  factory ParamEntry.fromJson(Map<String, dynamic> json) {
    return ParamEntry(
      key: _asString(json['key'], ''),
      value: _asString(json['value'], ''),
      label: _asString(json['label'], ''),
      extra: _collectExtra(json, knownKeys),
    );
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'key': key,
      'value': value,
      'label': label,
    };
    _appendExtra(out, extra);
    return out;
  }

  ParamEntry copy() => ParamEntry(
        key: key,
        value: value,
        label: label,
        extra: _deepCopyMap(extra),
      );
}

/// One pinned signal: `lib/config.h` `PinItem`.
///
/// Field names are camelCase Dart; the wire names are the C struct's snake_case
/// members, which are also the JSON keys (see [knownKeys] / [toJson]).
class PinItem {
  PinItem({
    this.type = PinItemType.url,
    this.name = '',
    this.intervalMs = 5000,
    this.url = '',
    this.reqHeaders = '',
    this.fieldExpr = '',
    this.clickEnabled = false,
    this.clickUrl = '',
    this.luaPath = '',
    List<ParamEntry>? params,
    this.pinned = false,
    this.barWidth = 0,
    this.barX = -1,
    this.barY = -1,
    this.barBgColor = kColorUseGlobal,
    this.dlgX = -1,
    this.dlgY = -1,
    this.dlgW = 0,
    this.dlgH = 0,
    Map<String, dynamic>? extra,
  })  : params = params ?? <ParamEntry>[],
        extra = extra ?? <String, dynamic>{};

  /// `PinItem.type` — [PinItemType.url] or [PinItemType.lua].
  int type;

  /// `PinItem.name`. C load default when the key is absent or not a string is
  /// `L"Untitled"` (`config.c:117`); an explicit `""` in the file is preserved
  /// as empty (7 of the 8 items in the real config.json are `""`).
  String name;

  /// `PinItem.interval_ms`.
  int intervalMs;

  /// URL mode: `PinItem.url`.
  String url;

  /// URL mode: `PinItem.req_headers`. A raw header block, e.g.
  /// `"x-api-key:sk-...\r\n"`.
  String reqHeaders;

  /// URL mode: `PinItem.field_expr`. Either a `$.path` template or Lua code;
  /// the distinction is a runtime heuristic in `src/expression.c`, so this is
  /// kept as an opaque string.
  String fieldExpr;

  /// URL mode: `PinItem.click_enabled`.
  bool clickEnabled;

  /// URL mode: `PinItem.click_url`.
  String clickUrl;

  /// Lua mode: `PinItem.lua_path`.
  String luaPath;

  /// `PinItem.params[CFG_MAX_PARAMS]`; the C `param_count` is [params].length.
  List<ParamEntry> params;

  /// `PinItem.pinned`.
  bool pinned;

  /// `PinItem.bar_width`, 0 = use global default.
  int barWidth;

  /// `PinItem.bar_x`, -1 = auto position.
  int barX;

  /// `PinItem.bar_y`, -1 = auto position.
  int barY;

  /// `PinItem.bar_bg_color` as a raw BGR hex string.
  /// [kColorUseGlobal] means "fall back to the global bg color".
  String barBgColor;

  /// `PinItem.dlg_x`, -1 = center.
  int dlgX;

  /// `PinItem.dlg_y`, -1 = center.
  int dlgY;

  /// `PinItem.dlg_w`, 0 = use script default.
  int dlgW;

  /// `PinItem.dlg_h`, 0 = use script default.
  int dlgH;

  /// Unknown keys found on this object, preserved verbatim across a round-trip.
  final Map<String, dynamic> extra;

  /// `PinItem.realtime` (config.h:49) is intentionally NOT modelled: it appears
  /// exactly once in the entire repository — its own declaration — and is never
  /// read, written, or serialised. It is listed here so that a stray key in an
  /// old file is treated as known-and-discarded rather than as an unknown key
  /// that would be round-tripped forever.
  static const Set<String> deadKeys = <String>{'realtime'};

  /// Wire key order, matching `config_save` (lib/config.c:398-415).
  static const List<String> wireOrder = <String>[
    'type',
    'name',
    'url',
    'req_headers',
    'interval_ms',
    'field_expr',
    'click_enabled',
    'click_url',
    'lua_path',
    'pinned',
    'bar_width',
    'bar_x',
    'bar_y',
    'bar_bg_color',
    'dlg_x',
    'dlg_y',
    'dlg_w',
    'dlg_h',
    // NOTE: 'params' is appended last and only when non-empty; see toJson().
  ];

  static final Set<String> knownKeys = <String>{
    ...wireOrder,
    'params',
    ...deadKeys,
  };

  /// `lib/config.c` `param_count`.
  int get paramCount => params.length;

  factory PinItem.fromJson(Map<String, dynamic> json) {
    return PinItem(
      type: _asInt(json['type'], PinItemType.url),
      name: _asString(json['name'], 'Untitled'),
      intervalMs: _asInt(json['interval_ms'], 5000),
      url: _asString(json['url'], ''),
      reqHeaders: _asString(json['req_headers'], ''),
      fieldExpr: _asString(json['field_expr'], ''),
      clickEnabled: _asBool(json['click_enabled'], false),
      clickUrl: _asString(json['click_url'], ''),
      luaPath: _asString(json['lua_path'], ''),
      params: _asList(json['params'])
          .map((e) => ParamEntry.fromJson(_asMap(e)))
          .toList(growable: true),
      pinned: _asBool(json['pinned'], false),
      barWidth: _asInt(json['bar_width'], 0),
      barX: _asInt(json['bar_x'], -1),
      barY: _asInt(json['bar_y'], -1),
      barBgColor: _asString(json['bar_bg_color'], kColorUseGlobal),
      dlgX: _asInt(json['dlg_x'], -1),
      dlgY: _asInt(json['dlg_y'], -1),
      dlgW: _asInt(json['dlg_w'], 0),
      dlgH: _asInt(json['dlg_h'], 0),
      extra: _collectExtra(json, knownKeys),
    );
  }

  /// Serialises in `config_save` order.
  ///
  /// Deliberately replicates two C behaviours:
  ///  * `params` is OMITTED entirely when empty (`config.c:417`
  ///    `if (it->param_count > 0)`), never written as `[]`. Five of the eight
  ///    items in the real config.json rely on this; emitting `[]` would break
  ///    round-trip equality.
  ///  * numbers stay integers, because `cJSON_AddNumberToObject` +
  ///    `item->valueint` means `5000.0` never appears in a C-written file.
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'type': type,
      'name': name,
      'url': url,
      'req_headers': reqHeaders,
      'interval_ms': intervalMs,
      'field_expr': fieldExpr,
      'click_enabled': clickEnabled,
      'click_url': clickUrl,
      'lua_path': luaPath,
      'pinned': pinned,
      'bar_width': barWidth,
      'bar_x': barX,
      'bar_y': barY,
      'bar_bg_color': barBgColor,
      'dlg_x': dlgX,
      'dlg_y': dlgY,
      'dlg_w': dlgW,
      'dlg_h': dlgH,
    };
    if (params.isNotEmpty) {
      out['params'] = params.map((p) => p.toJson()).toList(growable: false);
    }
    _appendExtra(out, extra);
    return out;
  }

  PinItem copy() => PinItem(
        type: type,
        name: name,
        intervalMs: intervalMs,
        url: url,
        reqHeaders: reqHeaders,
        fieldExpr: fieldExpr,
        clickEnabled: clickEnabled,
        clickUrl: clickUrl,
        luaPath: luaPath,
        params: params.map((p) => p.copy()).toList(growable: true),
        pinned: pinned,
        barWidth: barWidth,
        barX: barX,
        barY: barY,
        barBgColor: barBgColor,
        dlgX: dlgX,
        dlgY: dlgY,
        dlgW: dlgW,
        dlgH: dlgH,
        extra: _deepCopyMap(extra),
      );
}

/// The whole config file: `lib/config.h` `TaskPinConfig` plus the `version`
/// field that `config.c` writes but the C struct does not model.
class TaskPinConfig {
  TaskPinConfig({
    this.version = kUnifiedConfigVersion,
    List<PinItem>? items,
    this.width = 320,
    this.posX = -1,
    this.posY = -1,
    this.fontSize = 9,
    this.fontColor = 'FFFFFF',
    this.bgColor = 'FFFFFFFF',
    this.scrollEnabled = true,
    this.logLevel = 0,
    List<String>? sources,
    Map<String, dynamic>? globalExtra,
    Map<String, dynamic>? extra,
  })  : items = items ?? <PinItem>[],
        sources = sources ?? <String>['bestK/taskpin-plugins'],
        globalExtra = globalExtra ?? <String, dynamic>{},
        extra = extra ?? <String, dynamic>{};

  /// The `"version"` root key. `lib/config.c` writes a literal 1 and never
  /// reads it; the C struct has no such field. Modelled explicitly so that a
  /// future format can be detected and refused.
  int version;

  /// `TaskPinConfig.items[CFG_MAX_ITEMS]`; the C `count` is [items].length.
  List<PinItem> items;

  /// `TaskPinConfig.width`.
  int width;

  /// `TaskPinConfig.pos_x`, -1 = auto (left of the tray notify area).
  int posX;

  /// `TaskPinConfig.pos_y`, -1 = auto.
  int posY;

  /// `TaskPinConfig.font_size`, point size, default 9.
  int fontSize;

  /// `TaskPinConfig.font_color`, 6-digit BGR hex. Written with `%06X`, so any
  /// alpha the user typed is masked away on save.
  String fontColor;

  /// `TaskPinConfig.bg_color`, 8-digit BGR hex. The C comment says
  /// `0xFFFFFFFF` means transparent, but the value is handed straight to
  /// `CreateSolidBrush` (src/bar_window.c:94-96), where it is opaque. The real
  /// config.json carries `"00000000"`, which is opaque black, not transparent.
  String bgColor;

  /// `TaskPinConfig.scroll_enabled`.
  bool scrollEnabled;

  /// `TaskPinConfig.log_level`, 0=off 1=error 2=info 3=debug.
  int logLevel;

  /// `TaskPinConfig.sources[CFG_MAX_SOURCES]`; the C `source_count` is
  /// [sources].length. Note `config.c:166-169` injects
  /// `["bestK/taskpin-plugins"]` whenever the loaded list is empty, so an
  /// explicit `"sources": []` is NOT round-trippable through the C layer and
  /// is intentionally not round-trippable here either.
  List<String> sources;

  /// Unknown keys found inside the `"global"` object.
  final Map<String, dynamic> globalExtra;

  /// Unknown keys found at the document root.
  final Map<String, dynamic> extra;

  /// `lib/config.c` `count`.
  int get count => items.length;

  /// `lib/config.c` `source_count`.
  int get sourceCount => sources.length;

  static const Set<String> knownGlobalKeys = <String>{
    'width',
    'pos_x',
    'pos_y',
    'font_size',
    'font_color',
    'bg_color',
    'scroll_enabled',
    'log_level',
  };

  static const Set<String> knownRootKeys = <String>{
    'version',
    'global',
    'items',
    'sources',
  };

  /// Parses a decoded JSON document.
  ///
  /// [enforceVersion] makes a `version` greater than [kUnifiedConfigVersion]
  /// throw [ConfigVersionError] instead of being read. Leave it on for any
  /// file coming off disk.
  factory TaskPinConfig.fromJson(
    Map<String, dynamic> json, {
    String path = '<memory>',
    bool enforceVersion = true,
  }) {
    final version = _asInt(json['version'], kUnifiedConfigVersion);
    if (enforceVersion && version > kUnifiedConfigVersion) {
      throw ConfigVersionError(version: version, path: path);
    }

    final global = _asMap(json['global']);

    return TaskPinConfig(
      version: version,
      items: _asList(json['items'])
          .map((e) => PinItem.fromJson(_asMap(e)))
          .toList(growable: true),
      width: _asInt(global['width'], 320),
      posX: _asInt(global['pos_x'], -1),
      posY: _asInt(global['pos_y'], -1),
      fontSize: _asInt(global['font_size'], 9),
      fontColor: _asString(global['font_color'], 'FFFFFF'),
      bgColor: _asString(global['bg_color'], 'FFFFFFFF'),
      scrollEnabled: _asBool(global['scroll_enabled'], true),
      logLevel: _asInt(global['log_level'], 0),
      sources: _resolveSources(json['sources']),
      globalExtra: _collectExtra(global, knownGlobalKeys),
      extra: _collectExtra(json, knownRootKeys),
    );
  }

  /// Parses a JSON string. Throws [ConfigFormatError] if it is not a JSON
  /// object.
  factory TaskPinConfig.fromJsonString(
    String source, {
    String path = '<memory>',
    bool enforceVersion = true,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ConfigFormatError(path, 'not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw ConfigFormatError(
          path, 'expected a JSON object at the root, got ${decoded.runtimeType}');
    }
    return TaskPinConfig.fromJson(
      decoded.cast<String, dynamic>(),
      path: path,
      enforceVersion: enforceVersion,
    );
  }

  /// Serialises in `config_save` order: version, global, items, sources.
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'version': version,
      'global': <String, dynamic>{
        'width': width,
        'pos_x': posX,
        'pos_y': posY,
        'font_size': fontSize,
        'font_color': fontColor,
        'bg_color': bgColor,
        'scroll_enabled': scrollEnabled,
        'log_level': logLevel,
      },
      'items': items.map((i) => i.toJson()).toList(growable: false),
      'sources': sources.toList(growable: false),
    };
    _appendExtra(out['global'] as Map<String, dynamic>, globalExtra);
    _appendExtra(out, extra);
    return out;
  }

  /// Pretty-prints with tab indentation, matching `cJSON_Print` so that a diff
  /// against a C-written file stays clean.
  String toJsonString({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('\t')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// `config.c:166-169`: an absent or empty `sources` list becomes the default
  /// single source.
  static List<String> _resolveSources(dynamic raw) {
    final list = _asList(raw)
        .where((e) => e is String)
        .map((e) => e as String)
        .toList(growable: true);
    if (list.isEmpty) {
      return <String>['bestK/taskpin-plugins'];
    }
    return list;
  }
}

// ---------------------------------------------------------------------------
// Color helpers — the ONLY place that interprets the hex encoding.
// ---------------------------------------------------------------------------

/// Helpers for the BGR-hex ↔ integer encodings used on disk.
///
/// Two different conventions meet here and they are easy to confuse:
///
///  * **Config hex is BGR.** `"FF0000"` parses to `0x00FF0000`, which Win32
///    `CreateSolidBrush`/`SetTextColor` read as `RGB(0, 0, 255)` = **blue**.
///    This is the on-disk format and it must not change.
///  * **Script hex is RGB.** A Lua `font("#FF0000")` goes through
///    `parse_color_str` (`lib/scripting.c:149-160`), which builds the value
///    with `RGB(r, g, b)`, so the same literal means **red**.
///
/// The two paths therefore disagree on the meaning of identical text, and both
/// feed `src/bar_window.c:191`. The new UI must not inherit that ambiguity: it
/// should present a real color picker (or label the field as BGR) and keep the
/// on-disk bytes exactly as they are.
class ConfigColor {
  const ConfigColor._();

  /// Parses an on-disk color string to its raw 32-bit value.
  ///
  /// Mirrors `wcstoul(s, NULL, 16)`: leading whitespace and an optional `0x`
  /// prefix are accepted, parsing stops at the first non-hex character, and an
  /// unparsable string yields 0. Returns `null` when the input is not a usable
  /// string, so callers can distinguish "absent" from "black".
  static int? tryParse(String? hex) {
    if (hex == null) return null;
    final trimmed = hex.trim();
    if (trimmed.isEmpty) return null;
    var body = trimmed;
    if (body.startsWith('0x') || body.startsWith('0X')) {
      body = body.substring(2);
    }
    final match = RegExp(r'^[0-9a-fA-F]+').firstMatch(body);
    if (match == null) return null;
    return int.tryParse(match.group(0)!, radix: 16);
  }

  /// `%06X` of the low 24 bits — how `global.font_color` is written.
  static String format6(int value) =>
      (value & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');

  /// `%08X` of the full value — how `bg_color` and `bar_bg_color` are written.
  static String format8(int value) =>
      (value & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');

  /// A COLORREF (`0x00BBGGRR`) as the ARGB int Flutter wants (`0xAARRGGBB`).
  ///
  /// Assumes a fully opaque result, which is what the C layer actually renders
  /// regardless of the alpha byte.
  static int colorrefToArgb(int colorref) {
    final r = colorref & 0xFF;
    final g = (colorref >> 8) & 0xFF;
    final b = (colorref >> 16) & 0xFF;
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  /// The inverse of [colorrefToArgb]; the alpha byte is dropped because
  /// COLORREF has no room for it.
  static int argbToColorref(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return (b << 16) | (g << 8) | r;
  }

  /// True when an item's `bar_bg_color` means "use the global bg color".
  ///
  /// Exact string match, mirroring `src/bar_window.c:93`. Deliberately not
  /// case-insensitive: the C code compares the parsed integer, and this
  /// compares the string, so the comparison is on the canonical form the
  /// writer produces.
  static bool isUseGlobal(String barBgColor) => barBgColor == kColorUseGlobal;
}

// ---------------------------------------------------------------------------
// JSON coercion helpers
//
// `lib/config.c` uses typed readers that fall back to a default when the value
// is the wrong type (json_read_wstr / json_read_int / json_read_bool). These
// helpers reproduce that: a wrong-typed value behaves exactly like an absent
// one. `extra` is the exception — unknown KEYS are preserved, but a known key
// with a wrong type is silently defaulted, same as C.
// ---------------------------------------------------------------------------

String _asString(dynamic v, String fallback) => v is String ? v : fallback;

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return fallback;
}

bool _asBool(dynamic v, bool fallback) => v is bool ? v : fallback;

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// Everything in [json] whose key is not in [known].
Map<String, dynamic> _collectExtra(
    Map<String, dynamic> json, Set<String> known) {
  final extra = <String, dynamic>{};
  for (final entry in json.entries) {
    if (!known.contains(entry.key)) {
      extra[entry.key] = _deepCopy(entry.value);
    }
  }
  return extra;
}

void _appendExtra(Map<String, dynamic> out, Map<String, dynamic> extra) {
  for (final entry in extra.entries) {
    // Never let a preserved unknown key shadow a known one.
    out.putIfAbsent(entry.key, () => _deepCopy(entry.value));
  }
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> src) =>
    _deepCopy(src).cast<String, dynamic>();

dynamic _deepCopy(dynamic v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), _deepCopy(value)));
  }
  if (v is List) return v.map(_deepCopy).toList(growable: false);
  return v;
}
