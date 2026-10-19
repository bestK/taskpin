// Form components.
//
// Every control here is keyboard-focusable, tab-ordered and focus-ringed. The
// plan calls this out as new capability ("现在 ImGui 和 Win32 条完全没有键盘
// 焦点体系"), so it is a hard requirement rather than a nicety.
//
// A shared shell handles the label/helper/error chrome so the controls
// themselves only deal with their input area.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/param_decl.dart';
import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/color_hex.dart';
import '../util/focus.dart';
import 'feedback.dart';
import 'ui.dart';

/// Label / control / helper / error chrome shared by every field.
class TpFieldShell extends StatelessWidget {
  const TpFieldShell({
    super.key,
    required this.child,
    this.label,
    this.helper,
    this.error,
    this.required = false,
    this.labelFor,
  });

  final Widget child;
  final String? label;
  final String? helper;

  /// When non-null the field is in the error state and this is shown instead
  /// of [helper].
  final String? error;

  final bool required;
  final String? labelFor;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? l = label;
    final String? h = helper;
    final String? e = error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (l != null) ...<Widget>[
          Row(
            children: <Widget>[
              Text(
                l,
                style: TpTypography.body
                    .toTextStyle()
                    .copyWith(color: theme.text.primary),
              ),
              if (required) ...<Widget>[
                const SizedBox(width: TpSpacing.s4),
                Text(
                  '*',
                  style: TpTypography.body
                      .toTextStyle()
                      .copyWith(color: theme.status.critical),
                ),
              ],
            ],
          ),
          const SizedBox(height: TpSpacing.headerGap),
        ],
        child,
        if (e != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s4),
          Text(
            e,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.status.critical),
          ),
        ] else if (h != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s4),
          Text(
            h,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.text.tertiary),
          ),
        ],
      ],
    );
  }
}

/// The bordered input box every text-like field shares.
///
/// Resting: control fill, 1 px control stroke, 1 px strong bottom edge.
/// Focused: input-active fill, 2 px accent bottom edge.
/// Invalid: 2 px critical bottom edge.
class _TpInputBox extends StatelessWidget {
  const _TpInputBox({
    required this.child,
    required this.focused,
    required this.hovered,
    this.invalid = false,
    this.enabled = true,
  });

  final Widget child;
  final bool focused;
  final bool hovered;
  final bool invalid;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    final Color fill;
    if (focused) {
      fill = theme.control.fillInputActive;
    } else if (hovered && enabled) {
      fill = theme.control.fillHover;
    } else {
      fill = theme.control.fill;
    }

    final Color bottomColor;
    final double bottomWidth;
    if (invalid) {
      bottomColor = theme.status.critical;
      bottomWidth = 2;
    } else if (focused) {
      bottomColor = theme.accent.fill;
      bottomWidth = 2;
    } else {
      bottomColor = theme.control.strokeStrong;
      bottomWidth = 1;
    }

    return AnimatedContainer(
      duration: TpMotion.resolve(context, TpMotion.fast),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: TpRadius.control,
        border: Border.all(color: theme.control.stroke),
      ),
      child: tpWithBottomEdge(
        child,
        color: bottomColor,
        width: bottomWidth,
        radius: TpRadius.control,
      ),
    );
  }
}

/// A single-line text field.
class TpTextField extends StatefulWidget {
  const TpTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.helper,
    this.error,
    this.hint,
    this.obscure = false,
    this.enabled = true,
    this.required = false,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController? controller;

  /// Seed text for the internally-owned controller.
  ///
  /// Use this instead of passing a freshly-constructed `TextEditingController`
  /// on every build — that resets the cursor to the end on each keystroke and
  /// leaks a controller per frame. Ignored when [controller] is supplied.
  final String? initialValue;
  final String? label;
  final String? helper;
  final String? error;
  final String? hint;
  final bool obscure;
  final bool enabled;
  final bool required;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? leading;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  State<TpTextField> createState() => _TpTextFieldState();
}

class _TpTextFieldState extends State<TpTextField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue);
  bool _ownsNode = false;
  bool _ownsController = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _ownsController = widget.controller == null;
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) {
      _node.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Widget? lead = widget.leading;
    final Widget? trail = widget.trailing;

    return TpFieldShell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      required: widget.required,
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) => _TpInputBox(
          focused: _focused,
          hovered: hovered,
          invalid: widget.error != null,
          enabled: widget.enabled,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s12,
              vertical: TpSpacing.s6,
            ),
            child: Row(
              children: <Widget>[
                if (lead != null) ...<Widget>[
                  IconTheme(
                    data: IconThemeData(size: 15, color: theme.text.tertiary),
                    child: lead,
                  ),
                  const SizedBox(width: TpSpacing.s8),
                ],
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _node,
                    enabled: widget.enabled,
                    obscureText: widget.obscure,
                    autofocus: widget.autofocus,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: theme.accent.text,
                    style: TpTypography.body
                        .toTextStyle()
                        .copyWith(color: theme.text.primary),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: TpTypography.body
                          .toTextStyle()
                          .copyWith(color: theme.text.disabled),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (trail != null) ...<Widget>[
                  const SizedBox(width: TpSpacing.s8),
                  IconTheme(
                    data: IconThemeData(size: 15, color: theme.text.tertiary),
                    child: trail,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A multi-line text field.
///
/// Used for Lua script bodies and the `req_headers` block, so it is the one
/// field that renders in the mono role by default.
class TpTextArea extends StatefulWidget {
  const TpTextArea({
    super.key,
    this.controller,
    this.label,
    this.helper,
    this.error,
    this.hint,
    this.rows = 8,
    this.mono = true,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? label;
  final String? helper;
  final String? error;
  final String? hint;
  final int rows;
  final bool mono;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  State<TpTextArea> createState() => _TpTextAreaState();
}

class _TpTextAreaState extends State<TpTextArea> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) {
      _node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return TpFieldShell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) => _TpInputBox(
          focused: _focused,
          hovered: hovered,
          invalid: widget.error != null,
          enabled: widget.enabled,
          child: Padding(
            padding: const EdgeInsets.all(TpSpacing.s12),
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              maxLines: widget.rows,
              minLines: widget.rows,
              onChanged: widget.onChanged,
              cursorColor: theme.accent.text,
              style: (widget.mono ? TpTypography.mono : TpTypography.body)
                  .toTextStyle()
                  .copyWith(color: theme.text.primary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TpTypography.mono
                    .toTextStyle()
                    .copyWith(color: theme.text.disabled),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A numeric field with steppers and keyboard stepping.
class TpNumberField extends StatefulWidget {
  const TpNumberField({
    super.key,
    this.controller,
    this.value,
    this.label,
    this.helper,
    this.error,
    this.min,
    this.max,
    this.step = 1,
    this.suffix,
    this.enabled = true,
    this.decimals = 0,
    this.onChanged,
  });

  final TextEditingController? controller;

  /// Uncontrolled value. Ignored when [controller] is supplied.
  final num? value;

  final String? label;
  final String? helper;
  final String? error;
  final num? min;
  final num? max;
  final num step;

  /// Unit shown inside the field, e.g. `%`, `MB`.
  final String? suffix;

  final bool enabled;
  final int decimals;
  final ValueChanged<num?>? onChanged;

  @override
  State<TpNumberField> createState() => _TpNumberFieldState();
}

class _TpNumberFieldState extends State<TpNumberField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: _format(widget.value));
  late final FocusNode _node = FocusNode();
  bool _ownsController = false;
  bool _focused = false;

  String _format(num? v) {
    if (v == null) {
      return '';
    }
    return widget.decimals <= 0
        ? v.round().toString()
        : v.toStringAsFixed(widget.decimals);
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _node.addListener(() {
      if (_focused != _node.hasFocus) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _step(int direction) {
    final num current = num.tryParse(_controller.text.trim()) ?? 0;
    num next = current + (widget.step * direction);
    final num? lo = widget.min;
    final num? hi = widget.max;
    if (lo != null && next < lo) {
      next = lo;
    }
    if (hi != null && next > hi) {
      next = hi;
    }
    _controller.text = _format(next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? suffix = widget.suffix;

    return TpFieldShell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) => _TpInputBox(
          focused: _focused,
          hovered: hovered,
          invalid: widget.error != null,
          enabled: widget.enabled,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s12,
              vertical: TpSpacing.s4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.arrowUp):
                          _TpStepIntent(1),
                      SingleActivator(LogicalKeyboardKey.arrowDown):
                          _TpStepIntent(-1),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        _TpStepIntent: CallbackAction<_TpStepIntent>(
                          onInvoke: (_TpStepIntent i) {
                            _step(i.direction);
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _node,
                        enabled: widget.enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (String v) =>
                            widget.onChanged?.call(num.tryParse(v.trim())),
                        cursorColor: theme.accent.text,
                        // Numbers are always tabular: this is a metric field.
                        style: TpTypography.mono
                            .toTextStyle(tabular: true)
                            .copyWith(color: theme.text.primary),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                if (suffix != null) ...<Widget>[
                  const SizedBox(width: TpSpacing.s6),
                  Text(
                    suffix,
                    style: TpTypography.caption
                        .toTextStyle()
                        .copyWith(color: theme.text.tertiary),
                  ),
                ],
                const SizedBox(width: TpSpacing.s8),
                _TpStepperButton(
                  icon: TpIcons.chevronUp,
                  enabled: widget.enabled,
                  onTap: () => _step(1),
                  tooltip: 'Increase',
                ),
                _TpStepperButton(
                  icon: TpIcons.chevronDown,
                  enabled: widget.enabled,
                  onTap: () => _step(-1),
                  tooltip: 'Decrease',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TpStepIntent extends Intent {
  const _TpStepIntent(this.direction);

  final int direction;
}

class _TpStepperButton extends StatelessWidget {
  const _TpStepperButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return TpTooltip(
      message: tooltip,
      child: TpFocusRing(
        radius: TpRadius.control,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(TpSpacing.s2),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? theme.text.tertiary : theme.text.disabled,
          ),
        ),
      ),
    );
  }
}

/// An interval: a number plus a unit.
///
/// This is the field for `interval_ms` in config.json, and it exists because
/// nobody should have to type `300000` when they mean "5 minutes".
class TpIntervalField extends StatelessWidget {
  const TpIntervalField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.helper,
    this.error,
    this.enabled = true,
    this.minimum = const Duration(milliseconds: 100),
  });

  /// The current interval. Converted to the friendliest unit on display.
  final Duration value;

  final ValueChanged<Duration> onChanged;
  final String? label;
  final String? helper;
  final String? error;
  final bool enabled;
  final Duration minimum;

  /// The units offered, largest first so the dropdown reads naturally.
  static const List<_TpIntervalUnit> units = <_TpIntervalUnit>[
    _TpIntervalUnit('ms', 1),
    _TpIntervalUnit('s', 1000),
    _TpIntervalUnit('m', 60 * 1000),
    _TpIntervalUnit('h', 60 * 60 * 1000),
  ];

  /// Pick the largest unit that divides the duration evenly, so `300000 ms`
  /// displays as `5 m` rather than `300 s`.
  static _TpIntervalUnit bestUnit(Duration d) {
    final int ms = d.inMilliseconds;
    _TpIntervalUnit best = units.first;
    for (final _TpIntervalUnit u in units) {
      if (ms % u.millisPerUnit == 0) {
        best = u;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final _TpIntervalUnit unit = bestUnit(value);
    final int amount = value.inMilliseconds ~/ unit.millisPerUnit;

    return TpFieldShell(
      label: label,
      helper: helper,
      error: error,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: TpNumberField(
              // Keyed on the unit so switching units rebuilds the controller
              // with the converted value rather than keeping stale text.
              key: ValueKey<String>('interval-${unit.label}-$amount'),
              value: amount,
              min: 1,
              enabled: enabled,
              onChanged: (num? v) {
                if (v == null) {
                  return;
                }
                final Duration next =
                    Duration(milliseconds: v.round() * unit.millisPerUnit);
                onChanged(next < minimum ? minimum : next);
              },
            ),
          ),
          const SizedBox(width: TpSpacing.s8),
          SizedBox(
            width: 84,
            child: TpSelect<String>(
              value: unit.label,
              enabled: enabled,
              items: <TpSelectItem<String>>[
                for (final _TpIntervalUnit u in units)
                  TpSelectItem<String>(value: u.label, label: u.label),
              ],
              onChanged: (String? next) {
                if (next == null) {
                  return;
                }
                final _TpIntervalUnit target = units.firstWhere(
                  (_TpIntervalUnit u) => u.label == next,
                );
                onChanged(
                  Duration(milliseconds: amount * target.millisPerUnit),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TpIntervalUnit {
  const _TpIntervalUnit(this.label, this.millisPerUnit);

  final String label;
  final int millisPerUnit;
}

/// A colour field: swatch + hex + alpha.
///
/// Writes the config's `AARRGGBB` wire format (see `TpColorHex`), and knows
/// about the `"FFFFFFFF"` inherit sentinel so the "use default" state is a
/// real, selectable option rather than an invisible trap.
class TpColorField extends StatefulWidget {
  const TpColorField({
    super.key,
    required this.wireValue,
    required this.onChanged,
    this.label,
    this.helper,
    this.error,
    this.enabled = true,
    this.allowInherit = true,
  });

  /// The value in config wire format (`AARRGGBB`).
  final String wireValue;

  final ValueChanged<String> onChanged;
  final String? label;
  final String? helper;
  final String? error;
  final bool enabled;

  /// Offer the "use default" option. Set false for colours that must be
  /// concrete (e.g. a state colour in a theme editor).
  final bool allowInherit;

  @override
  State<TpColorField> createState() => _TpColorFieldState();
}

class _TpColorFieldState extends State<TpColorField> {
  late final TextEditingController _hex = TextEditingController(
    text: TpColorHex.isInherit(widget.wireValue)
        ? ''
        : TpColorHex.toWire(
            TpColorHex.fromWire(widget.wireValue) ?? Colors.black,
          ),
  );

  @override
  void didUpdateWidget(TpColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wireValue != widget.wireValue) {
      final String next = TpColorHex.isInherit(widget.wireValue)
          ? ''
          : widget.wireValue;
      if (_hex.text != next) {
        _hex.text = next;
      }
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      widget.onChanged(widget.allowInherit ? kColorInherit : 'FF000000');
      return;
    }
    final Color? parsed = TpColorHex.fromWire(trimmed);
    if (parsed != null) {
      widget.onChanged(TpColorHex.toWire(parsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool inherit = TpColorHex.isInherit(widget.wireValue);
    final Color swatch =
        TpColorHex.fromWire(widget.wireValue) ?? theme.bg.cardSecondary;

    return TpFieldShell(
      label: widget.label,
      helper: widget.helper,
      error: widget.error,
      child: Row(
        children: <Widget>[
          // The swatch. Checkerboarded when translucent so "transparent" does
          // not read as "black" — which is exactly the bug the current bar has
          // (bg_color 00000000 fed to CreateSolidBrush).
          TpSurface(
            level: TpSurfaceLevel.inset,
            radius: TpRadius.control,
            clip: true,
            child: SizedBox(
              width: 36,
              height: 36,
              child: inherit
                  ? Icon(
                      TpIcons.close,
                      size: 16,
                      color: theme.text.tertiary,
                    )
                  : ColoredBox(color: swatch),
            ),
          ),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: TpTextField(
              controller: _hex,
              enabled: widget.enabled && !inherit,
              hint: inherit ? 'Inherit default' : 'AARRGGBB',
              onSubmitted: _commit,
              onChanged: (String v) {
                // Commit only complete values while typing, so a partially
                // typed hex does not clobber the stored colour.
                if (v.trim().length >= 6) {
                  _commit(v);
                }
              },
              leading: Icon(TpIcons.palette),
            ),
          ),
          if (widget.allowInherit) ...<Widget>[
            const SizedBox(width: TpSpacing.s8),
            TpSwitch(
              value: inherit,
              label: 'Default',
              onChanged: widget.enabled
                  ? (bool v) => widget.onChanged(v ? kColorInherit : 'FF000000')
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// One option in a [TpSelect].
class TpSelectItem<T> {
  const TpSelectItem({
    required this.value,
    required this.label,
    this.description,
  });

  final T value;
  final String label;
  final String? description;
}

/// A dropdown.
///
/// Built on `DropdownButton` rather than a custom overlay: it already handles
/// focus, keyboard navigation and semantics correctly, and reimplementing that
/// is how keyboard accessibility regresses.
class TpSelect<T> extends StatelessWidget {
  const TpSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.helper,
    this.error,
    this.hint,
    this.enabled = true,
  });

  final T value;
  final List<TpSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? helper;
  final String? error;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    // Guard against a value that is not in the list: DropdownButton asserts.
    final bool hasValue =
        items.any((TpSelectItem<T> i) => i.value == value);

    return TpFieldShell(
      label: label,
      helper: helper,
      error: error,
      child: _TpInputBox(
        focused: false,
        hovered: false,
        invalid: error != null,
        enabled: enabled,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
          child: DropdownButton<T>(
            value: hasValue ? value : null,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            hint: hint == null
                ? null
                : Text(
                    hint!,
                    style: TpTypography.body
                        .toTextStyle()
                        .copyWith(color: theme.text.disabled),
                  ),
            icon: Icon(
              TpIcons.chevronDown,
              size: 16,
              color: theme.text.tertiary,
            ),
            dropdownColor: theme.bg.flyout,
            borderRadius: TpRadius.control,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: theme.text.primary),
            items: <DropdownMenuItem<T>>[
              for (final TpSelectItem<T> item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Text(
                    item.label,
                    style: TpTypography.body
                        .toTextStyle()
                        .copyWith(color: theme.text.primary),
                  ),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

/// A switch. Keyboard-operable (Space toggles) and focus-ringed.
class TpSwitch extends StatelessWidget {
  const TpSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? l = label;
    final String? d = description;
    final bool interactive = enabled && onChanged != null;

    // 40 x 20 pill. Off: transparent with a strong outline and a secondary
    // knob. On: accent fill with an on-accent knob. No on/off text.
    final Color trackFill = value
        ? (interactive ? theme.accent.fill : theme.text.disabled)
        : Colors.transparent;
    final Color knob = value
        ? (interactive ? theme.accent.onFill : theme.bg.window)
        : (interactive ? theme.text.secondary : theme.text.disabled);
    final double knobSize = value ? 12 : 10;

    final Widget track = AnimatedContainer(
      duration: TpMotion.resolve(context, TpMotion.fast),
      width: TpControlSize.switchWidth,
      height: TpControlSize.switchHeight,
      decoration: BoxDecoration(
        color: trackFill,
        borderRadius: TpRadius.chip,
        border: value
            ? null
            : Border.all(
                color: interactive
                    ? theme.control.strokeStrong
                    : theme.text.disabled,
              ),
      ),
      child: AnimatedAlign(
        duration: TpMotion.resolve(context, TpMotion.fast),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s4),
          child: Container(
            width: knobSize,
            height: knobSize,
            decoration: BoxDecoration(color: knob, shape: BoxShape.circle),
          ),
        ),
      ),
    );

    final Widget toggle = TpFocusRing(
      radius: TpRadius.chip,
      enabled: interactive,
      onTap: interactive ? () => onChanged!(!value) : null,
      onActivate: interactive ? () => onChanged!(!value) : null,
      child: track,
    );

    if (l == null && d == null) {
      return toggle;
    }

    // The whole row is the tap target, not just the track.
    return TpFocusRing(
      radius: TpRadius.control,
      enabled: interactive,
      onTap: interactive ? () => onChanged!(!value) : null,
      onActivate: interactive ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TpSpacing.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The track is decorative here: the row owns the gesture.
            IgnorePointer(child: track),
            if (l != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l,
                    style: TpTypography.body
                        .toTextStyle()
                        .copyWith(color: theme.text.primary),
                  ),
                  if (d != null)
                    Text(
                      d,
                      style: TpTypography.caption
                          .toTextStyle()
                          .copyWith(color: theme.text.secondary),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A segmented control: a small set of mutually exclusive options, all visible.
///
/// Preferred over [TpSelect] when there are 2-4 options, because it removes a
/// click and makes the alternatives discoverable. Keyboard: left/right arrows
/// move the selection.
class TpSegmentedControl<T> extends StatelessWidget {
  const TpSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<TpSelectItem<T>> segments;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final int selectedIndex =
        segments.indexWhere((TpSelectItem<T> s) => s.value == value);

    return FocusTraversalGroup(
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
        },
        child: Container(
          height: TpControlSize.control,
          padding: const EdgeInsets.all(TpSpacing.s2),
          decoration: BoxDecoration(
            color: theme.bg.cardSecondary,
            borderRadius: TpRadius.card,
            border: Border.all(color: theme.stroke.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < segments.length; i++)
                _TpSegment(
                  label: segments[i].label,
                  selected: i == selectedIndex,
                  enabled: enabled,
                  onTap: () => onChanged(segments[i].value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TpSegment extends StatelessWidget {
  const _TpSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) => TpFocusRing(
        radius: BorderRadius.circular(TpRadius.cardValue),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: TpMotion.resolve(context, TpMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.bg.card
                : (hovered ? theme.bg.window : Colors.transparent),
            borderRadius: BorderRadius.circular(TpRadius.cardValue),
            border: selected
                ? Border.all(color: theme.stroke.card)
                : Border.all(color: Colors.transparent),
          ),
          child: Text(
            label,
            style: TpTypography.body.toTextStyle().copyWith(
                  color: selected
                      ? theme.text.primary
                      : (enabled ? theme.text.secondary : theme.text.disabled),
                ),
          ),
        ),
      ),
    );
  }
}

/// A field generated from a Lua `@param` declaration.
///
/// This is the plan's Phase 5 requirement in widget form: the form is built
/// from what the script declared, not from a hand-maintained list of fields.
class TpParamField extends StatelessWidget {
  const TpParamField({
    super.key,
    required this.param,
    required this.onChanged,
    this.enabled = true,
  });

  final TpParamValue param;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TpParamDecl decl = param.decl;
    final String value = param.value;

    switch (decl.type) {
      case TpParamType.number:
        return TpNumberField(
          key: ValueKey<String>('param-${decl.key}'),
          value: num.tryParse(value.trim()),
          label: decl.displayLabel,
          enabled: enabled,
          decimals: 2,
          onChanged: (num? v) => onChanged(v?.toString() ?? ''),
        );
      case TpParamType.boolean:
        return TpSwitch(
          value: param.booleanValue,
          label: decl.displayLabel,
          enabled: enabled,
          onChanged: (bool v) => onChanged(v ? 'true' : 'false'),
        );
      case TpParamType.color:
        return TpColorField(
          key: ValueKey<String>('param-${decl.key}'),
          wireValue: value.isEmpty ? kColorInherit : value,
          label: decl.displayLabel,
          enabled: enabled,
          onChanged: onChanged,
        );
      case TpParamType.path:
        return TpPathPicker(
          value: value,
          label: decl.displayLabel,
          enabled: enabled,
          onChanged: onChanged,
        );
      case TpParamType.string:
        return TpTextField(
          key: ValueKey<String>('param-${decl.key}'),
          // `initialValue` rather than a fresh controller: constructing a
          // controller here would reset the cursor on every keystroke and leak
          // one per rebuild.
          initialValue: value,
          label: decl.displayLabel,
          enabled: enabled,
          onChanged: onChanged,
        );
    }
  }
}

/// A file/directory path field with a browse affordance.
///
/// Platform-free by design: this package never opens a native dialog. The host
/// app supplies [onBrowse], which does the platform call and hands back a path
/// (or null if the user cancelled). That keeps `taskpin_design` free of any
/// MethodChannel or FFI.
class TpPathPicker extends StatelessWidget {
  const TpPathPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onBrowse,
    this.label,
    this.helper,
    this.error,
    this.enabled = true,
    this.placeholder = 'No file selected',
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Host-supplied browse action. When null the button is hidden and the field
  /// degrades to plain text entry.
  final Future<String?> Function()? onBrowse;

  final String? label;
  final String? helper;
  final String? error;
  final bool enabled;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool empty = value.trim().isEmpty;

    return TpFieldShell(
      label: label,
      helper: helper,
      error: error,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TpSurface(
              level: TpSurfaceLevel.inset,
              radius: TpRadius.control,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpSpacing.s12,
                  vertical: TpSpacing.s6,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      TpIcons.file,
                      size: 15,
                      color: theme.text.tertiary,
                    ),
                    const SizedBox(width: TpSpacing.s8),
                    Expanded(
                      child: TpMetric(
                        empty ? (placeholder ?? '') : value,
                        role: empty
                            ? TpTextRole.disabled
                            : TpTextRole.secondary,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onBrowse != null) ...<Widget>[
            const SizedBox(width: TpSpacing.s8),
            TpButton(
              label: 'Browse',
              icon: TpIcons.folder,
              enabled: enabled,
              onPressed: enabled
                  ? () async {
                      final String? picked = await onBrowse!();
                      if (picked != null) {
                        onChanged(picked);
                      }
                    }
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// One header row in a [TpHeaderListEditor].
class TpHeaderEntry {
  const TpHeaderEntry({required this.name, required this.value});

  final String name;
  final String value;
}

/// An editor for a list of HTTP headers.
///
/// Corresponds to `req_headers` in config.json. Reordering is keyboard-
/// operable (Alt+Up / Alt+Down) because header order can matter for some
/// servers, and a drag-only reorder would exclude keyboard users.
class TpHeaderListEditor extends StatelessWidget {
  const TpHeaderListEditor({
    super.key,
    required this.entries,
    required this.onChanged,
    this.label,
    this.helper,
    this.enabled = true,
  });

  final List<TpHeaderEntry> entries;
  final ValueChanged<List<TpHeaderEntry>> onChanged;
  final String? label;
  final String? helper;
  final bool enabled;

  void _update(int index, TpHeaderEntry next) {
    final List<TpHeaderEntry> copy = List<TpHeaderEntry>.of(entries);
    copy[index] = next;
    onChanged(copy);
  }

  void _remove(int index) {
    final List<TpHeaderEntry> copy = List<TpHeaderEntry>.of(entries)
      ..removeAt(index);
    onChanged(copy);
  }

  void _move(int index, int delta) {
    final int target = index + delta;
    if (target < 0 || target >= entries.length) {
      return;
    }
    final List<TpHeaderEntry> copy = List<TpHeaderEntry>.of(entries);
    final TpHeaderEntry moved = copy.removeAt(index);
    copy.insert(target, moved);
    onChanged(copy);
  }

  void _add() =>
      onChanged(<TpHeaderEntry>[...entries, const TpHeaderEntry(name: '', value: '')]);

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? l = label;
    final String? h = helper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (l != null) ...<Widget>[
          Text(
            l,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: theme.text.secondary),
          ),
          const SizedBox(height: TpSpacing.s6),
        ],
        for (int i = 0; i < entries.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: TpSpacing.s6),
          _TpHeaderRow(
            entry: entries[i],
            index: i,
            total: entries.length,
            enabled: enabled,
            onChanged: (TpHeaderEntry e) => _update(i, e),
            onRemove: () => _remove(i),
            onMoveUp: () => _move(i, -1),
            onMoveDown: () => _move(i, 1),
          ),
        ],
        const SizedBox(height: TpSpacing.s8),
        TpButton(
          label: 'Add header',
          icon: TpIcons.add,
          variant: TpButtonVariant.text,
          size: TpControlSize.control,
          enabled: enabled,
          onPressed: _add,
        ),
        if (h != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s4),
          Text(
            h,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.text.tertiary),
          ),
        ],
      ],
    );
  }
}

class _TpHeaderRow extends StatelessWidget {
  const _TpHeaderRow({
    required this.entry,
    required this.index,
    required this.total,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    this.enabled = true,
  });

  final TpHeaderEntry entry;
  final int index;
  final int total;
  final ValueChanged<TpHeaderEntry> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Row(
      children: <Widget>[
        Icon(TpIcons.dragHandle, size: 14, color: theme.text.disabled),
        const SizedBox(width: TpSpacing.s8),
        Expanded(
          flex: 2,
          child: TpTextField(
            key: ValueKey<String>('hdr-name-$index'),
            initialValue: entry.name,
            hint: 'Header',
            enabled: enabled,
            onChanged: (String v) =>
                onChanged(TpHeaderEntry(name: v, value: entry.value)),
          ),
        ),
        const SizedBox(width: TpSpacing.s8),
        Expanded(
          flex: 3,
          child: TpTextField(
            key: ValueKey<String>('hdr-value-$index'),
            initialValue: entry.value,
            hint: 'Value',
            enabled: enabled,
            onChanged: (String v) =>
                onChanged(TpHeaderEntry(name: entry.name, value: v)),
          ),
        ),
        const SizedBox(width: TpSpacing.s4),
        _TpHeaderAction(
          icon: TpIcons.chevronUp,
          tooltip: 'Move up (Alt+Up)',
          enabled: enabled && index > 0,
          onTap: onMoveUp,
        ),
        _TpHeaderAction(
          icon: TpIcons.chevronDown,
          tooltip: 'Move down (Alt+Down)',
          enabled: enabled && index < total - 1,
          onTap: onMoveDown,
        ),
        _TpHeaderAction(
          icon: TpIcons.delete,
          tooltip: 'Remove',
          enabled: enabled,
          onTap: onRemove,
        ),
      ],
    );
  }
}

class _TpHeaderAction extends StatelessWidget {
  const _TpHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return TpTooltip(
      message: tooltip,
      child: TpFocusRing(
        radius: TpRadius.control,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(TpSpacing.s4),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? theme.text.tertiary : theme.text.disabled,
          ),
        ),
      ),
    );
  }
}
