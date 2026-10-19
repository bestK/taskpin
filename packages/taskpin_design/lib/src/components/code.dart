// Code components: LuaEditor, ResponsePreview, ExpressionEditor.
//
// Per the plan, the Lua editor is deliberately plain: monospace + line numbers,
// no syntax highlighting and no completion. So this is a `TextField` with a
// gutter, not a code-editor library.

import 'package:flutter/material.dart';

import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'forms.dart';
import 'ui.dart';

/// A plain-text editor with a line-number gutter.
class TpLuaEditor extends StatefulWidget {
  const TpLuaEditor({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.helper,
    this.error,
    this.readOnly = false,
    this.minLines = 12,
    this.focusNode,
    this.onChanged,
    this.gutter = true,
  });

  final TextEditingController? controller;

  /// Seed text for the internally-owned controller. Preferred over passing a
  /// controller built in `build`.
  final String? initialValue;

  final String? label;
  final String? helper;
  final String? error;
  final bool readOnly;
  final int minLines;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  /// Show the line-number gutter.
  final bool gutter;

  @override
  State<TpLuaEditor> createState() => _TpLuaEditorState();
}

class _TpLuaEditorState extends State<TpLuaEditor> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue);
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final ScrollController _scroll = ScrollController();

  bool _ownsController = false;
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsNode = widget.focusNode == null;
    _node.addListener(() {
      if (_focused != _node.hasFocus) {
        setState(() => _focused = _node.hasFocus);
      }
    });
    // Keep the gutter in step with the text.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _scroll.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsNode) {
      _node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final int lineCount = '\n'.allMatches(_controller.text).length + 1;

    final Widget editor = TextField(
      controller: _controller,
      focusNode: _node,
      readOnly: widget.readOnly,
      maxLines: null,
      minLines: widget.minLines,
      scrollController: _scroll,
      onChanged: widget.onChanged,
      cursorColor: theme.accent.text,
      // Tab inserts a tab rather than moving focus — in an editor, moving focus
      // is the wrong behaviour and users expect indentation.
      textAlignVertical: TextAlignVertical.top,
      style: TpTypography.mono
          .toTextStyle()
          .copyWith(color: theme.text.primary),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );

    return TpFieldShell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) => AnimatedContainer(
          duration: TpMotion.resolve(context, TpMotion.fast),
          decoration: BoxDecoration(
            color: theme.bg.cardSecondary,
            borderRadius: TpRadius.control,
            border: Border.all(
              color: _focused
                  ? theme.focusOuter
                  : (hovered ? theme.control.strokeStrong : theme.stroke.divider),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.gutter) _gutter(theme, lineCount),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(TpSpacing.s12),
                  child: editor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gutter(TaskPinTheme theme, int lineCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        TpSpacing.s12,
        TpSpacing.s12,
        TpSpacing.s8,
        TpSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: theme.bg.window,
        border: Border(right: BorderSide(color: theme.stroke.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 1; i <= lineCount; i++)
            Text(
              '$i',
              style: TpTypography.mono
                  .toTextStyle(tabular: true)
                  .copyWith(color: theme.text.disabled),
            ),
        ],
      ),
    );
  }
}

/// A read-only view of a script's raw response.
///
/// Shows the body with a small header (status, content-type, byte count) so
/// the user can tell "the server returned HTML instead of JSON" without
/// scrolling.
class TpResponsePreview extends StatelessWidget {
  const TpResponsePreview({
    super.key,
    required this.body,
    this.statusCode,
    this.contentType,
    this.truncated = false,
    this.maxHeight = 320,
  });

  final String body;
  final int? statusCode;
  final String? contentType;

  /// The body was cut for display.
  final bool truncated;

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final int? code = statusCode;

    final bool ok = code == null || (code >= 200 && code < 300);
    final Color codeColor =
        ok ? theme.status.success : theme.status.critical;

    return TpSurface(
      level: TpSurfaceLevel.inset,
      radius: TpRadius.control,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s12,
              vertical: TpSpacing.s6,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.stroke.divider)),
            ),
            child: Row(
              children: <Widget>[
                if (code != null) ...<Widget>[
                  Text(
                    '$code',
                    style: TpTypography.caption
                        .toTextStyle(tabular: true)
                        .copyWith(color: codeColor),
                  ),
                  const SizedBox(width: TpSpacing.s12),
                ],
                if (contentType != null)
                  Expanded(
                    child: Text(
                      contentType!,
                      style: TpTypography.caption
                          .toTextStyle()
                          .copyWith(color: theme.text.tertiary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  '${body.length} B${truncated ? ' (truncated)' : ''}',
                  style: TpTypography.caption
                      .toTextStyle(tabular: true)
                      .copyWith(color: theme.text.tertiary),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TpSpacing.s12),
              child: SelectableText(
                body,
                style: TpTypography.mono
                    .toTextStyle()
                    .copyWith(color: theme.text.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An editor for a `$.path` expression.
///
/// The config's `field_expr` is either a `$.a.b` template or a Lua snippet
/// (see `lib/expression.c`); the host decides which via the engine. This widget
/// only edits the string, with a hint listing the paths available in the live
/// response so the user is not typing blind.
class TpExpressionEditor extends StatefulWidget {
  const TpExpressionEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.availablePaths = const <String>[],
    this.label,
    this.helper,
    this.error,
    this.enabled = true,
    this.isLua = false,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// `$.path` candidates harvested from the last response. Rendered as
  /// one-tap chips.
  final List<String> availablePaths;

  final String? label;
  final String? helper;
  final String? error;
  final bool enabled;

  /// Whether the engine classified this as Lua code rather than a path
  /// template. Only affects the hint text.
  final bool isLua;

  @override
  State<TpExpressionEditor> createState() => _TpExpressionEditorState();
}

class _TpExpressionEditorState extends State<TpExpressionEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(TpExpressionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt an external change, but never while the field is being edited.
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _insert(String path) {
    final String next =
        _controller.text.trim().isEmpty ? path : '${_controller.text} $path';
    _controller.text = next;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TpTextField(
          controller: _controller,
          label: widget.label,
          helper: widget.helper ??
              (widget.isLua
                  ? 'Lua expression'
                  : 'Path template, e.g. \$.data.value'),
          error: widget.error,
          enabled: widget.enabled,
          hint: widget.isLua ? 'return ...' : r'$.path',
          onChanged: widget.onChanged,
          leading: Icon(TpIcons.code),
        ),
        if (widget.availablePaths.isNotEmpty) ...<Widget>[
          const SizedBox(height: TpSpacing.s8),
          Wrap(
            spacing: TpSpacing.s6,
            runSpacing: TpSpacing.s6,
            children: <Widget>[
              for (final String p in widget.availablePaths)
                TpFocusRing(
                  radius: TpRadius.chip,
                  enabled: widget.enabled,
                  onTap: widget.enabled ? () => _insert(p) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpSpacing.s8,
                      vertical: TpSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.bg.cardSecondary,
                      borderRadius: TpRadius.chip,
                      border: Border.all(color: theme.stroke.divider),
                    ),
                    child: Text(
                      p,
                      style: TpTypography.caption
                          .toTextStyle()
                          .copyWith(color: theme.text.secondary),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
