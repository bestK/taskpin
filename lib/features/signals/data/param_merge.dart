// Merges a script's `-- @param` declarations with the values stored in
// config.json.
//
// The plan's Phase 5 criterion is that the parameter form is "由引擎解析器自动
// 生成而非手维护" — generated from what the script declares, not from a
// hand-maintained field list. So the declaration list is authoritative for which
// fields EXIST and in what ORDER, and config.json is authoritative for what they
// are SET TO.
//
// The two can disagree, and both directions matter:
//
//   * Declared but not stored — a script gained a new `@param` since the item
//     was configured. The field appears, empty, so the user can fill it in.
//   * Stored but not declared — the script dropped or renamed a `@param`. The
//     stored value is NOT discarded here. Silently dropping it would lose user
//     data on a config rewrite, and `lib/config.c` has no way to express "keep
//     this but do not show it". So undeclared entries are kept, marked, and
//     rendered in a separate group; only the user can remove them.
//
// Imports only pure-Dart files (`config_schema.dart`, `lua_header.dart`), so the
// merge rules are unit-testable without a Flutter SDK.

import '../../../core/config/config_schema.dart';
import 'lua_header.dart';

/// One parameter as the editor should present it.
class ResolvedParam {
  const ResolvedParam({
    required this.key,
    required this.type,
    required this.label,
    required this.value,
    required this.declared,
  });

  /// The key the Lua script reads (`args.KEY`).
  final String key;

  /// The declared type token, e.g. `string`, `number`, `color`. Empty when the
  /// entry is undeclared.
  final String type;

  /// Display label: the declaration's label, else the stored label, else the
  /// key. Never empty.
  final String label;

  /// The current value from config.json, or '' when never set.
  final String value;

  /// True when a `-- @param` line declares this key.
  final bool declared;

  /// The label to render.
  String get displayLabel => label.isEmpty ? key : label;

  ResolvedParam withValue(String next) => ResolvedParam(
        key: key,
        type: type,
        label: label,
        value: next,
        declared: declared,
      );

  @override
  String toString() => 'ResolvedParam($key=$value, type=$type, '
      'declared=$declared)';
}

/// The merge result, split so the editor can render two groups.
class ResolvedParams {
  const ResolvedParams({required this.declared, required this.undeclared});

  /// In declaration order. Every key here has a `-- @param` line.
  final List<ResolvedParam> declared;

  /// Stored values with no matching declaration, in their original stored
  /// order. Rendered separately so nothing is lost on the next save.
  final List<ResolvedParam> undeclared;

  /// Everything, declared first. This is the order to persist.
  List<ResolvedParam> get all => <ResolvedParam>[...declared, ...undeclared];

  bool get isEmpty => declared.isEmpty && undeclared.isEmpty;

  /// Project back to the config model, preserving order and dropping nothing.
  ///
  /// The label written is the resolved one, matching how `lib/config.c` stores
  /// what it parsed (`script_parse_params` fills `ParamEntry.label` from the
  /// declaration).
  List<ParamEntry> toParamEntries() => all
      .map((ResolvedParam p) => ParamEntry(
            key: p.key,
            value: p.value,
            label: p.label,
          ))
      .toList(growable: true);
}

/// Merges [declarations] with [stored].
///
/// Duplicate declarations of the same key: the FIRST wins, matching
/// `tp_parse_params`, which would produce two entries but whose consumers
/// (`lib/scripting.c`) look keys up by name and so see the first. Keeping one
/// entry avoids writing a duplicate key into config.json.
ResolvedParams mergeParams({
  required List<LuaHeaderParam> declarations,
  required List<ParamEntry> stored,
}) {
  final Map<String, ParamEntry> byKey = <String, ParamEntry>{};
  for (final ParamEntry e in stored) {
    // First stored entry wins, for the same reason.
    byKey.putIfAbsent(e.key, () => e);
  }

  final List<ResolvedParam> declared = <ResolvedParam>[];
  final Set<String> declaredKeys = <String>{};

  for (final LuaHeaderParam d in declarations) {
    if (!declaredKeys.add(d.key)) continue; // duplicate declaration
    final ParamEntry? existing = byKey[d.key];
    declared.add(ResolvedParam(
      key: d.key,
      type: d.type,
      // Prefer the script's label; fall back to whatever was stored.
      label: d.label.isNotEmpty ? d.label : (existing?.label ?? ''),
      value: existing?.value ?? '',
      declared: true,
    ));
  }

  final List<ResolvedParam> undeclared = <ResolvedParam>[];
  for (final ParamEntry e in stored) {
    if (declaredKeys.contains(e.key)) continue;
    // A duplicate stored key was already handled by byKey; skip the second.
    if (undeclared.any((ResolvedParam r) => r.key == e.key)) continue;
    undeclared.add(ResolvedParam(
      key: e.key,
      type: '',
      label: e.label,
      value: e.value,
      declared: false,
    ));
  }

  return ResolvedParams(declared: declared, undeclared: undeclared);
}

/// Builds the initial `params` for a newly added item: every declared parameter
/// present with an empty value, so the user sees the full form immediately.
///
/// Deliberately does NOT invent values for `required` declarations — there is no
/// default syntax in the `@param` grammar (see `TpParamDecl.defaultValue`, which
/// is reserved and currently unreachable).
List<ParamEntry> initialParamsFor(List<LuaHeaderParam> declarations) =>
    mergeParams(declarations: declarations, stored: const <ParamEntry>[])
        .toParamEntries();
