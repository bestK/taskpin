// The project detail page (docs/VISUAL_SPEC.md section 5.4).
//
// Covers every field of `PinItem`:
//
//   type, name, url, req_headers, field_expr, interval_ms, click_enabled,
//   click_url, lua_path, params, pinned, bar_width, bar_x, bar_y,
//   bar_bg_color, dlg_x, dlg_y, dlg_w, dlg_h
//
// Every change goes through `ConfigNotifier.editItem`, whose repository
// debounces writes by 500 ms. There is no save button.
//
// `bar_bg_color` uses `ConfigColorField`, which converts the stored BGR
// COLORREF for display and back on commit. `params` is driven by the script's
// own `-- @param` header.
//
// The click action select maps onto the existing fields without a format
// change:
//
//   none    click_enabled = false
//   link    click_enabled = true, click_url = the link
//   popup   click_enabled = true, click_url = ''  (the script's dialog opens)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart'
    show ClickAction, EngineApi, ParamDecl, ScriptResult;

import '../../app/l10n.dart';
import '../../app/shell/app_page.dart';
import '../../app/shell/routes.dart';
import '../../app/windows/dialog_window.dart';
import '../../core/bar/bar_source.dart'
    show ResolvedBarContent, resolveContent;
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../core/engine/engine_provider.dart';
import '../../core/engine/engine_run.dart';
import '../../core/net/http_providers.dart';
import '../dialogs/dialog_spec.dart' as dlg;
import 'data/lua_header.dart' show LuaHeader, LuaHeaderParam;
import 'data/param_merge.dart';
import 'data/req_headers_codec.dart';
import 'widgets/config_color_field.dart';
import 'widgets/item_labels.dart';

/// What a click on the taskbar item does.
enum ClickMode { none, link, popup }

/// Width of text and select controls on a settings card.
const double kControlWidth = 280;

/// Width of the script path field.
const double kPathFieldWidth = 400;

/// The detail page for one item.
class SignalsEditorPage extends ConsumerStatefulWidget {
  const SignalsEditorPage({super.key, required this.index});

  /// Index into `TaskPinConfig.items`.
  final int index;

  @override
  ConsumerState<SignalsEditorPage> createState() => _SignalsEditorPageState();
}

class _SignalsEditorPageState extends ConsumerState<SignalsEditorPage> {
  /// The script header, once read. Null while loading.
  LuaHeader? _header;

  /// Which `lua_path` [_header] was read for.
  String? _headerFor;

  /// Set when the engine could not read the header.
  String? _headerError;

  /// Last run output, or null before the first run.
  TpBarContent? _content;

  /// Last run result from the engine (Lua items only).
  ScriptResult? _result;

  /// Error text of the last run, or null when it succeeded.
  String? _runError;

  /// Duration and wall-clock time of the last run.
  Duration? _runDuration;
  DateTime? _runAt;

  bool _running = false;

  /// The selected click action. Kept in state so "link" stays selected while
  /// the link field is still empty.
  late ClickMode _clickMode;

  /// Opens (and reuses) the popup window for this item.
  final DialogWindowHost _dialogHost = DialogWindowHost();

  bool get _valid =>
      widget.index >= 0 &&
      widget.index < ref.read(configProvider).items.length;

  PinItem get _item => ref.read(configProvider).items[widget.index];

  @override
  void initState() {
    super.initState();
    if (_valid) {
      _clickMode = _modeOf(_item);
      _loadHeader();
      // Run once when the page opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _valid) _run();
      });
    } else {
      _clickMode = ClickMode.none;
    }
  }

  static ClickMode _modeOf(PinItem item) {
    if (!item.clickEnabled) return ClickMode.none;
    return item.clickUrl.trim().isNotEmpty ? ClickMode.link : ClickMode.popup;
  }

  /// Applies [mutate] to this item and saves.
  void _edit(void Function(PinItem item) mutate) =>
      ref.read(configProvider.notifier).editItem(widget.index, mutate);

  /// Reads `-- @param` and `-- @refresh` from the item's script through the
  /// engine, the same parser the taskbar uses.
  Future<void> _loadHeader() async {
    final PinItem item = _item;
    final String path = item.luaPath.trim();
    if (item.type != PinItemType.lua || path.isEmpty) {
      setState(() {
        _header = LuaHeader.empty;
        _headerFor = null;
        _headerError = null;
      });
      return;
    }
    setState(() {
      _headerFor = path;
      _headerError = null;
    });
    try {
      final EngineApi engine = await ref.read(engineProvider.future);
      final List<ParamDecl> decls = await engine.parseParams(path);
      final int refresh = await engine.parseRefresh(path);
      if (!mounted || _headerFor != path) return;
      setState(() {
        _header = LuaHeader(
          params: <LuaHeaderParam>[
            for (final ParamDecl d in decls)
              LuaHeaderParam(key: d.key, type: d.type, label: d.label),
          ],
          refreshMs: refresh,
        );
      });
    } catch (e) {
      if (!mounted || _headerFor != path) return;
      setState(() {
        _header = LuaHeader.empty;
        _headerError = '$e';
      });
    }
  }

  /// Runs the item the way the taskbar does and records the output.
  ///
  /// A Lua error is not an exception: it arrives in the result. Only a
  /// transport failure (engine missing, isolate died) throws.
  Future<void> _run() async {
    if (!_valid || _running) return;
    final PinItem item = _item;
    final bool hasSource = item.type == PinItemType.lua
        ? item.luaPath.trim().isNotEmpty
        : item.url.trim().isNotEmpty;
    if (!hasSource) {
      setState(() {
        _content = null;
        _result = null;
        _runError = null;
      });
      return;
    }

    setState(() => _running = true);
    final Stopwatch sw = Stopwatch()..start();
    try {
      final EngineApi engine = await ref.read(engineProvider.future);
      final ResolvedBarContent resolved = await resolveContent(
        engine: engine,
        item: item,
        fetcher: ref.read(httpFetcherProvider),
        baseDirectory: _baseDir(),
      );
      sw.stop();
      if (!mounted) return;
      setState(() {
        _running = false;
        _content = resolved.content;
        _result = resolved.result;
        _runError = resolved.failed ? (resolved.error ?? '') : null;
        _runDuration = sw.elapsed;
        _runAt = DateTime.now();
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _running = false;
        _content = null;
        _result = null;
        _runError = '$e';
        _runDuration = sw.elapsed;
        _runAt = DateTime.now();
      });
    }
  }

  String? _baseDir() {
    try {
      return ref.read(configRepositoryProvider).paths.baseDir;
    } on Object {
      return null;
    }
  }

  Future<void> _previewPopup(PinItem item, ScriptResult result) async {
    final dlg.DialogSpec? spec = dlg.DialogSpec.fromScriptResult(
      scriptResultToDialogMap(result),
    );
    if (spec == null) return;
    final bool opened = await _dialogHost.open(
      spec,
      luaPath: item.luaPath.trim(),
      argsJson: argsJsonFromParams(item.params),
    );
    if (!opened && mounted) {
      TpToastHost.show(
        context,
        TpToast(
          message: context.l10n.detailNoMultiWindow,
          kind: TpStateKind.caution,
        ),
      );
    }
  }

  Future<void> _confirmDelete(PinItem item) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await TpConfirmDialog.show(
      context,
      title: l10n.projectDeleteTitle,
      message: l10n.confirmDeleteDesc,
      detail: itemDisplayName(item, widget.index, l10n),
      confirmLabel: l10n.mainDelete,
      cancelLabel: l10n.editCancel,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    ref.read(configProvider.notifier).removeItemAt(widget.index);
    context.go(AppRoutes.signals);
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinConfig config = ref.watch(configProvider);
    if (widget.index < 0 || widget.index >= config.items.length) {
      // The item is gone (deleted, or a stale link). Go back to the list.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.signals);
      });
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = context.l10n;
    final PinItem item = config.items[widget.index];

    return AppPage(
      breadcrumb: <TpBreadcrumbSegment>[
        TpBreadcrumbSegment(
          label: l10n.navProjects,
          onTap: () => context.go(AppRoutes.signals),
        ),
        TpBreadcrumbSegment(label: itemDisplayName(item, widget.index, l10n)),
      ],
      actions: <Widget>[
        TpButton(
          label: l10n.detailRun,
          icon: TpIcons.play,
          enabled: !_running,
          onPressed: _run,
        ),
      ],
      children: <Widget>[
        _previewSection(context, item),
        _generalSection(context, item),
        _sourceSection(context, item),
        ..._paramsSection(context, item),
        _gap(_appearance(context, item)),
        _gap(_clickSection(context, item)),
        _gap(_deleteCard(context, item)),
      ],
    );
  }

  /// Space above a card that is not inside a titled section.
  Widget _gap(Widget child) => Padding(
        padding: const EdgeInsets.only(top: TpSpacing.sectionTop),
        child: child,
      );

  // -- Preview --------------------------------------------------------------

  Widget _previewSection(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);

    final TpBarContent? content = _content;
    final bool hasContent = content != null && !content.isEmpty;
    final bool failed = _runError != null;

    final Widget strip;
    if (hasContent) {
      strip = TpBarPreviewStrip(
        content: content,
        background: _bgColor(item.barBgColor),
        width: item.barWidth > 0 ? item.barWidth.toDouble() : null,
        state: failed ? TpBarState.error : TpBarState.running,
        showStateStrip: failed,
      );
    } else {
      final String text = _running
          ? l10n.detailRunning
          : (_runAt == null
              ? l10n.detailPreviewIdle
              : itemDisplayName(item, widget.index, l10n));
      strip = Text(
        text,
        style: TpTypography.caption
            .toTextStyle()
            .copyWith(color: theme.text.secondary),
      );
    }

    final Duration? duration = _runDuration;
    final DateTime? at = _runAt;
    final String meta = _running
        ? l10n.detailRunning
        : (duration == null || at == null
            ? ''
            : l10n.detailPreviewMeta(duration.inMilliseconds, _clock(at)));

    return TpSettingsSection(
      title: l10n.detailSectionPreview,
      children: <Widget>[
        _FieldCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 48,
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: theme.taskbarPreview,
                    borderRadius: TpRadius.control,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: strip,
                  ),
                ),
              ),
              if (meta.isNotEmpty) ...<Widget>[
                const SizedBox(width: TpSpacing.s16),
                Text(
                  meta,
                  style: TpTypography.caption
                      .toTextStyle(tabular: true)
                      .copyWith(color: theme.text.secondary),
                ),
              ],
            ],
          ),
        ),
        if (failed && _runError!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(TpSpacing.s12),
            decoration: BoxDecoration(
              color: theme.bg.cardSecondary,
              borderRadius: TpRadius.control,
            ),
            child: SelectableText(
              _runError!,
              style: TpTypography.mono
                  .toTextStyle()
                  .copyWith(color: theme.status.critical),
            ),
          ),
      ],
    );
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static Color? _bgColor(String wireValue) {
    if (ConfigColor.isUseGlobal(wireValue)) return null;
    final int? raw = ConfigColor.tryParse(wireValue);
    if (raw == null) return null;
    return Color(ConfigColor.colorrefToArgb(raw));
  }

  // -- General --------------------------------------------------------------

  Widget _generalSection(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    return TpSettingsSection(
      title: l10n.detailSectionGeneral,
      children: <Widget>[
        TpSettingsCard(
          title: l10n.detailName,
          trailing: SizedBox(
            width: kControlWidth,
            child: TpTextField(
              initialValue: item.name,
              hint: itemDisplayName(item, widget.index, l10n),
              onChanged: (String v) => _edit((PinItem i) => i.name = v),
            ),
          ),
        ),
        TpSettingsCard(
          title: l10n.detailType,
          trailing: SizedBox(
            width: kControlWidth,
            child: TpSelect<int>(
              value: item.type,
              items: <TpSelectItem<int>>[
                TpSelectItem<int>(
                  value: PinItemType.lua,
                  label: l10n.editTypeLua,
                ),
                TpSelectItem<int>(
                  value: PinItemType.url,
                  label: l10n.editTypeUrl,
                ),
              ],
              onChanged: (int? v) {
                if (v == null || v == item.type) return;
                _edit((PinItem i) => i.type = v);
                _loadHeader();
              },
            ),
          ),
        ),
        TpSettingsCard(
          title: l10n.detailInterval,
          trailing: SizedBox(
            width: kControlWidth,
            child: TpIntervalField(
              value: Duration(milliseconds: item.intervalMs),
              onChanged: (Duration d) =>
                  _edit((PinItem i) => i.intervalMs = d.inMilliseconds),
            ),
          ),
        ),
        TpSettingsCard(
          title: l10n.projectPinToTaskbar,
          trailing: TpSwitch(
            value: item.pinned,
            onChanged: (bool _) =>
                ref.read(configProvider.notifier).togglePinned(widget.index),
          ),
        ),
      ],
    );
  }

  // -- Data source ----------------------------------------------------------

  Widget _sourceSection(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    final List<Widget> cards;

    if (item.type == PinItemType.lua) {
      cards = <Widget>[
        TpSettingsCard(
          title: l10n.detailScriptFile,
          trailing: SizedBox(
            width: kPathFieldWidth,
            child: TpTextField(
              initialValue: item.luaPath,
              hint: l10n.detailScriptFileDesc,
              onChanged: (String v) {
                _edit((PinItem i) => i.luaPath = v);
                if (v.trim().endsWith('.lua')) _loadHeader();
              },
              onSubmitted: (String v) {
                _edit((PinItem i) => i.luaPath = v);
                _loadHeader();
              },
            ),
          ),
        ),
      ];
    } else {
      cards = <Widget>[
        TpSettingsCard(
          title: l10n.detailAddress,
          trailing: SizedBox(
            width: kPathFieldWidth,
            child: TpTextField(
              initialValue: item.url,
              onChanged: (String v) => _edit((PinItem i) => i.url = v),
            ),
          ),
        ),
        TpSettingsExpander(
          title: l10n.detailHeaders,
          initiallyExpanded: item.reqHeaders.trim().isNotEmpty,
          children: <Widget>[
            TpHeaderListEditor(
              entries: decodeHeaders(item.reqHeaders)
                  .map((HeaderPair p) =>
                      TpHeaderEntry(name: p.name, value: p.value))
                  .toList(growable: true),
              onChanged: (List<TpHeaderEntry> next) => _edit(
                (PinItem i) => i.reqHeaders = encodeHeaders(
                  next
                      .map((TpHeaderEntry e) =>
                          HeaderPair(name: e.name, value: e.value))
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
        TpSettingsExpander(
          title: l10n.detailExpression,
          initiallyExpanded: item.fieldExpr.trim().isNotEmpty,
          children: <Widget>[
            TpExpressionEditor(
              value: item.fieldExpr,
              availablePaths: _pathSuggestions(item.fieldExpr),
              onChanged: (String v) => _edit((PinItem i) => i.fieldExpr = v),
            ),
          ],
        ),
      ];
    }

    return TpSettingsSection(
      title: l10n.detailSectionSource,
      children: cards,
    );
  }

  /// `$.path` tokens already present in the expression, offered as chips.
  static List<String> _pathSuggestions(String current) {
    final List<String> seen = <String>[];
    for (final RegExpMatch m
        in RegExp(r'\$\.[A-Za-z_][A-Za-z0-9_.]*').allMatches(current)) {
      final String s = m.group(0)!;
      if (!seen.contains(s)) seen.add(s);
    }
    return seen;
  }

  // -- Parameters -----------------------------------------------------------

  List<Widget> _paramsSection(BuildContext context, PinItem item) {
    if (item.type != PinItemType.lua) return const <Widget>[];
    final LuaHeader? header = _header;
    if (header == null) return const <Widget>[];
    final AppLocalizations l10n = context.l10n;

    final String? headerError = _headerError;
    if (headerError != null) {
      return <Widget>[
        TpSettingsSection(
          title: l10n.detailSectionParams,
          children: <Widget>[
            TpInfoBar(
              kind: TpStateKind.caution,
              title: l10n.detailParamsError,
              message: headerError,
              actions: <Widget>[
                TpButton(
                  label: l10n.detailRetry,
                  icon: TpIcons.refresh,
                  onPressed: _loadHeader,
                ),
              ],
            ),
          ],
        ),
      ];
    }

    final ResolvedParams resolved = mergeParams(
      declarations: header.params,
      stored: item.params,
    );
    if (resolved.declared.isEmpty) return const <Widget>[];

    // Values for undeclared keys stay in the config. `_setParam` writes them
    // back unchanged.
    return <Widget>[
      TpSettingsSection(
        title: l10n.detailSectionParams,
        children: <Widget>[
          for (final ResolvedParam p in resolved.declared)
            _FieldCard(
              child: TpParamField(
                param: TpParamValue(
                  decl: TpParamDecl(
                    key: p.key,
                    type: TpParamType.fromWire(p.type),
                    label: p.displayLabel,
                  ),
                  value: p.value,
                ),
                onChanged: (String v) => _setParam(resolved, p.key, v),
              ),
            ),
        ],
      ),
    ];
  }

  /// Writes one parameter back, keeping every other entry (including the
  /// undeclared ones) in order.
  void _setParam(ResolvedParams resolved, String key, String value) {
    final List<ResolvedParam> next = resolved.all
        .map((ResolvedParam p) => p.key == key ? p.withValue(value) : p)
        .toList(growable: false);
    _edit((PinItem i) => i.params = next
        .map((ResolvedParam p) => ParamEntry(
              key: p.key,
              value: p.value,
              label: p.label,
            ))
        .toList(growable: true));
  }

  // -- Appearance -----------------------------------------------------------

  Widget _appearance(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    return TpSettingsExpander(
      title: l10n.detailAppearance,
      children: <Widget>[
        TpNumberField(
          value: item.barWidth,
          label: l10n.detailWidth,
          min: 0,
          max: 800,
          suffix: 'px',
          onChanged: (num? v) =>
              _edit((PinItem i) => i.barWidth = v?.round() ?? 0),
        ),
        ConfigColorField(
          wireValue: item.barBgColor,
          label: l10n.detailBackground,
          allowInherit: true,
          onChanged: (String v) => _edit((PinItem i) => i.barBgColor = v),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TpNumberField(
                value: item.barX,
                label: l10n.detailPosX,
                min: -1,
                onChanged: (num? v) =>
                    _edit((PinItem i) => i.barX = v?.round() ?? -1),
              ),
            ),
            const SizedBox(width: TpSpacing.s12),
            Expanded(
              child: TpNumberField(
                value: item.barY,
                label: l10n.detailPosY,
                min: -1,
                onChanged: (num? v) =>
                    _edit((PinItem i) => i.barY = v?.round() ?? -1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -- Click action ---------------------------------------------------------

  Widget _clickSection(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    final ScriptResult? result = _result;
    final bool canPreview = _clickMode == ClickMode.popup &&
        result != null &&
        result.clickable &&
        result.clickAction == ClickAction.dialog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TpSettingsCard(
          title: l10n.detailClickTitle,
          description: l10n.detailClickDesc,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (canPreview) ...<Widget>[
                TpButton(
                  label: l10n.detailPreviewDialog,
                  icon: TpIcons.externalLink,
                  variant: TpButtonVariant.text,
                  onPressed: () => _previewPopup(item, result),
                ),
                const SizedBox(width: TpSpacing.s8),
              ],
              SizedBox(
                width: 180,
                child: TpSelect<ClickMode>(
                  value: _clickMode,
                  items: <TpSelectItem<ClickMode>>[
                    TpSelectItem<ClickMode>(
                      value: ClickMode.none,
                      label: l10n.detailClickNone,
                    ),
                    TpSelectItem<ClickMode>(
                      value: ClickMode.link,
                      label: l10n.detailClickLink,
                    ),
                    TpSelectItem<ClickMode>(
                      value: ClickMode.popup,
                      label: l10n.detailClickDialog,
                    ),
                  ],
                  onChanged: (ClickMode? m) {
                    if (m == null) return;
                    setState(() => _clickMode = m);
                    switch (m) {
                      case ClickMode.none:
                        _edit((PinItem i) => i.clickEnabled = false);
                      case ClickMode.link:
                        _edit((PinItem i) => i.clickEnabled = true);
                      case ClickMode.popup:
                        _edit((PinItem i) {
                          i.clickEnabled = true;
                          i.clickUrl = '';
                        });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (_clickMode == ClickMode.link) ...<Widget>[
          const SizedBox(height: TpSpacing.settingsCardGap),
          TpSettingsCard(
            title: l10n.detailClickUrl,
            trailing: SizedBox(
              width: kPathFieldWidth,
              child: TpTextField(
                initialValue: item.clickUrl,
                onChanged: (String v) => _edit((PinItem i) => i.clickUrl = v),
              ),
            ),
          ),
        ],
        if (_clickMode == ClickMode.popup) ...<Widget>[
          const SizedBox(height: TpSpacing.settingsCardGap),
          TpSettingsExpander(
            title: l10n.detailDialogPlacement,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TpNumberField(
                      value: item.dlgX,
                      label: l10n.detailDialogX,
                      min: -1,
                      onChanged: (num? v) =>
                          _edit((PinItem i) => i.dlgX = v?.round() ?? -1),
                    ),
                  ),
                  const SizedBox(width: TpSpacing.s12),
                  Expanded(
                    child: TpNumberField(
                      value: item.dlgY,
                      label: l10n.detailDialogY,
                      min: -1,
                      onChanged: (num? v) =>
                          _edit((PinItem i) => i.dlgY = v?.round() ?? -1),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TpNumberField(
                      value: item.dlgW,
                      label: l10n.detailDialogW,
                      min: 0,
                      suffix: 'px',
                      onChanged: (num? v) =>
                          _edit((PinItem i) => i.dlgW = v?.round() ?? 0),
                    ),
                  ),
                  const SizedBox(width: TpSpacing.s12),
                  Expanded(
                    child: TpNumberField(
                      value: item.dlgH,
                      label: l10n.detailDialogH,
                      min: 0,
                      suffix: 'px',
                      onChanged: (num? v) =>
                          _edit((PinItem i) => i.dlgH = v?.round() ?? 0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  // -- Delete ---------------------------------------------------------------

  Widget _deleteCard(BuildContext context, PinItem item) {
    final AppLocalizations l10n = context.l10n;
    return TpSettingsCard(
      title: l10n.detailDeleteTitle,
      description: l10n.detailDeleteDesc,
      trailing: TpButton(
        label: l10n.mainDelete,
        icon: TpIcons.delete,
        onPressed: () => _confirmDelete(item),
      ),
    );
  }
}

/// A plain card around one control that brings its own label.
class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(TpSpacing.surfacePadding),
      decoration: BoxDecoration(
        color: theme.bg.card,
        borderRadius: TpRadius.control,
        border: Border.all(color: theme.stroke.card),
      ),
      child: child,
    );
  }
}
