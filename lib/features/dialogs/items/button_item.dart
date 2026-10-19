// A `DI_BUTTON` item — a full-width action.
//
// C parity (`lib/script_dialog.c:329-349` and the owner-draw at `:452-498`):
//   - the button spans the dialog width minus 12 px of padding each side
//     (`PADDING_X`, `:333`);
//   - it is 26 px tall (`btn_h = 26`, `:331`);
//   - the label is left-aligned with 8 px of leading inset (`:484`);
//   - background is the item's `bg`, defaulting to `RGB(50,50,50)` (`:467`);
//   - foreground is the item's `color`, defaulting to `RGB(220,220,220)` (`:468`);
//   - a 1 px `RGB(70,70,70)` border (`:490`);
//   - URL wins over command (`:509-513`), matching the table rows.
//
// `TpButton` supplies the focus ring, hover and keyboard activation the GDI
// button never had; the colours are overridden from the spec so a script's
// `bg`/`color` still win, which is the part of the C behaviour that is a
// contract rather than a look.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_action.dart';
import '../dialog_palette.dart';
import '../dialog_spec.dart';

class DialogButtonItem extends StatelessWidget {
  const DialogButtonItem({super.key, required this.item, required this.runner});

  final DialogItem item;
  final DialogActionRunner runner;

  /// C button height (`lib/script_dialog.c:331`).
  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color bg = dialogButtonBackground(theme, item.bg);
    final Color fg = dialogForeground(theme, item.color);

    return SizedBox(
      height: height,
      child: _SpecStyledButton(
        label: item.value.isEmpty ? 'Button' : item.value,
        background: bg,
        foreground: fg,
        onPressed: () => _activate(),
      ),
    );
  }

  /// URL first, then command (`lib/script_dialog.c:509-523`).
  void _activate() {
    if (item.url.isNotEmpty) {
      runner.openUrl(item.url);
      return;
    }
    if (item.cmd.isNotEmpty) {
      runner.runCommand(item.cmd);
    }
  }
}

/// A button that keeps `TpButton`'s focus/hover/keyboard behaviour but draws
/// the script's own colours.
///
/// Built on `TpFocusRing` + `TpHoverBuilder` rather than `TpButton` because
/// `TpButton` derives its skin from the theme's variants and offers no colour
/// override — and a script's `bg = "#333333"` is part of the dialog contract,
/// not decoration. The focus ring, hover feedback and Enter/Space activation
/// are the same widgets `TpButton` uses, so this is not a parallel component
/// so much as `TpButton` with the skin parameterised.
class _SpecStyledButton extends StatelessWidget {
  const _SpecStyledButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        // C brightens the fill by +30 on press (`lib/script_dialog.c:471-472`);
        // hover is the Aurora equivalent of that feedback.
        final Color fill = hovered
            ? Color.lerp(background, theme.text.primary, 0.12) ?? background
            : background;

        return TpFocusRing(
          radius: TpRadius.control,
          onTap: onPressed,
          onActivate: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: TpRadius.control,
              // C: 1 px RGB(70,70,70) border.
              border: Border.all(color: theme.control.strokeStrong),
            ),
            child: Padding(
              // C: 8 px leading inset, vertically centred (`:483-485`).
              padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: TpTypography.body.toTextStyle().copyWith(
                        color: foreground,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
