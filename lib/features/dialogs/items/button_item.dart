// A `DI_BUTTON` item — an action button.
//
// Rather than the legacy C dimensions (26 px tall, 8 px leading inset, heavy
// border — which made buttons read as text fields), the button adopts the
// platform standard 32 px control silhouette with centered label and 12 px
// horizontal padding.
//
// An explicit `bg` and `color` from the script contract still win over the theme
// defaults. When no script color is supplied, the button rests on `control.fill`
// with a `control.stroke` border, lifting to `control.fillHover` on hover.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_action.dart';
import '../dialog_palette.dart';
import '../dialog_spec.dart';

class DialogButtonItem extends StatelessWidget {
  const DialogButtonItem({super.key, required this.item, required this.runner});

  final DialogItem item;
  final DialogActionRunner runner;

  /// Control height matching `TpControlSize.control` (32 px).
  static const double height = TpControlSize.control;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: _SpecStyledButton(
        label: item.value.isEmpty ? 'Button' : item.value,
        customBg: parseDialogColor(item.bg),
        customFg: parseDialogColor(item.color),
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
/// the script's own colours when supplied.
///
/// Built on `TpFocusRing` + `TpHoverBuilder` rather than `TpButton` because
/// `TpButton` derives its skin from the theme's variants and offers no colour
/// override — and a script's `bg = "#333333"` is part of the dialog contract,
/// not decoration.
class _SpecStyledButton extends StatelessWidget {
  const _SpecStyledButton({
    required this.label,
    required this.customBg,
    required this.customFg,
    required this.onPressed,
  });

  final String label;
  final Color? customBg;
  final Color? customFg;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        // When no custom background is passed from the script, default to the
        // theme's control fill and lift to `control.fillHover` on hover.
        // If the script provided an explicit hex colour (part of the dialog
        // contract), preserve it and lighten slightly on hover.
        final Color background;
        if (customBg != null) {
          background = hovered
              ? Color.lerp(customBg!, theme.text.primary, 0.12) ?? customBg!
              : customBg!;
        } else {
          background = hovered ? theme.control.fillHover : theme.control.fill;
        }

        final Color foreground = customFg ?? theme.text.primary;

        return TpFocusRing(
          radius: TpRadius.control,
          onTap: onPressed,
          onActivate: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: TpRadius.control,
              border: Border.all(color: theme.control.stroke),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
              child: Center(
                child: Text(
                  label,
                  style: TpTypography.body.toTextStyle().copyWith(
                    color: foreground,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
