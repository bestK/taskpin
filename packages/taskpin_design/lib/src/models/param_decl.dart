// The `@param` declaration model.
//
// Lua scripts declare their editable parameters in a header comment:
//
//   -- @param BASE_URL string API地址(如 https://api.example.com)
//   -- @param USER_ID  number 用户ID
//   -- @refresh 5000
//
// `tp_parse_params` in the C engine parses these into `TPParamDecl[]`. This
// model is the Dart-side shape `TpParamField` renders from. The point of the
// plan's Phase 5 acceptance criterion ("`@param` 字段由引擎解析器自动生成而非
// 手维护") is that these declarations drive the form — so the form needs a
// type to bind to.
//
// The parser itself lives in the engine package. This file only defines the
// shape and the type mapping.

/// The parameter types a `@param` declaration can name.
///
/// Unknown types degrade to [string] rather than failing, matching the C
/// parser's tolerance (a script with a typo in its header must still run).
enum TpParamType {
  string('string'),
  number('number'),
  boolean('boolean'),
  color('color'),

  /// A file or directory path. Rendered with `TpPathPicker`.
  path('path');

  const TpParamType(this.wireName);

  /// The token used in the `@param` header.
  final String wireName;

  static TpParamType fromWire(String name) {
    final String n = name.trim().toLowerCase();
    for (final TpParamType t in TpParamType.values) {
      if (t.wireName == n) {
        return t;
      }
    }
    return TpParamType.string;
  }
}

/// One declared parameter.
class TpParamDecl {
  const TpParamDecl({
    required this.key,
    required this.type,
    required this.label,
    this.defaultValue = '',
    this.required = false,
  });

  /// The `KEY` — the name the Lua script reads it by.
  final String key;

  /// Declared type, which selects the form control.
  final TpParamType type;

  /// Human label from the header comment. Falls back to [key] when blank.
  final String label;

  /// Default value, if the declaration supplies one.
  final String defaultValue;

  /// Whether the field must be non-empty before the item can be saved.
  ///
  /// Not currently expressible in the `@param` syntax; reserved so the form
  /// does not need reshaping when it is added.
  final bool required;

  /// The label to actually display.
  String get displayLabel => label.isEmpty ? key : label;
}

/// A parameter declaration plus the user's current value.
///
/// This is what `TpParamField` takes: the declaration drives the control, the
/// value is what the config layer persists into `PinItem.params`.
class TpParamValue {
  const TpParamValue({required this.decl, this.value = ''});

  final TpParamDecl decl;
  final String value;

  /// The key, for convenience at call sites.
  String get key => decl.key;

  /// Parse the value according to the declared type.
  ///
  /// Never throws: a malformed value in a `number` field yields null and the
  /// form shows the error, rather than crashing the settings page.
  num? get numberValue => num.tryParse(value.trim());

  bool get booleanValue {
    final String v = value.trim().toLowerCase();
    return v == 'true' || v == '1' || v == 'yes' || v == 'on';
  }

  TpParamValue copyWith({String? value}) =>
      TpParamValue(decl: decl, value: value ?? this.value);
}
