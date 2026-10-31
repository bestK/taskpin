// A `DI_TEXT` item, with its optional inline icon.
//
// C parity (`lib/script_dialog.c:184-217`):
//   - the icon is drawn FIRST, then the text, on the same line;
//   - the icon box is `img_w`/`img_h`, each defaulting to the line height;
//   - the icon is vertically centred on the text line (`iy = y + (tm.tmHeight
//     - dh) / 2`);
//   - 4 px of gap between icon and text (`text_x += dw + 4`);
//   - the line height becomes `max(textHeight, iconHeight)` when the icon is
//     taller than the text.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_palette.dart';
import '../dialog_spec.dart';
import '../image_source.dart';

class DialogTextItem extends StatelessWidget {
  const DialogTextItem({super.key, required this.item, this.baseDirectory});

  final DialogItem item;

  /// Resolved against a relative `image` source, when the caller has one.
  final String? baseDirectory;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final DialogSurfaceContext? surfaceContext =
        DialogSurfaceContext.of(context);
    final Color? parsedColor = parseDialogColor(item.color);

    // Color contrast adaptation is strictly gated to macOS popover mode
    // (`hostDrawsSurface == true`), where native vibrant material or explicit
    // fill shows through. In Windows window mode (`hostDrawsSurface == false`),
    // script colours must stay strictly untouched.
    // The C default is 10 pt; a script that asks for a size gets exactly that
    // (lib/script_dialog.c:123, :185). The type scale is only used for the
    // default, so a script's `size = 24` is not silently re-rounded to a token.
    final double size = item.fontSize > 0
        ? dialogFontPixels(item.fontSize)
        : TpTypography.body.size;

    // WCAG 2.1 large text is at least 18.66 px bold or 24 px regular. Only
    // that gets the 3:1 floor; everything else needs 4.5:1.
    final bool largeText = item.bold ? size >= 18.66 : size >= 24;

    final Color? explicitColor;
    if (parsedColor != null) {
      if (surfaceContext != null && surfaceContext.hostDrawsSurface) {
        explicitColor = ensureContrast(
          parsedColor,
          surfaceContext.surfaceColor,
          minContrast: largeText ? 3.0 : 4.5,
        );
      } else {
        explicitColor = parsedColor;
      }
    } else {
      explicitColor = null;
    }
    final bool isLabel = _isLabel(item);
    final Color defaultColor =
        isLabel ? theme.text.secondary : theme.text.primary;
    final bool hasIcon = item.image.isNotEmpty;

    final TextStyle baseStyle = TpTypography.body.toTextStyle().copyWith(
      fontSize: size,
      fontWeight: item.bold ? FontWeight.w700 : null,
    );

    // If the script provided no explicit colour, check if this text has a
    // "Label: Value" pair so the label can step back to `text.secondary` while
    // the value remains prominent in `text.primary`.
    final Widget text;
    final Match? labelValueMatch = explicitColor == null && !isLabel
        ? _kLabelValuePattern.firstMatch(item.value)
        : null;

    if (labelValueMatch != null) {
      final String labelPart = labelValueMatch.group(1)!;
      final String space = labelValueMatch.group(2)!;
      final String valuePart = labelValueMatch.group(3)!;
      text = Text.rich(
        TextSpan(
          style: baseStyle,
          children: <InlineSpan>[
            TextSpan(
              text: '$labelPart$space',
              style: TextStyle(color: theme.text.secondary),
            ),
            TextSpan(
              text: valuePart,
              style: TextStyle(color: theme.text.primary),
            ),
          ],
        ),
        softWrap: true,
      );
    } else {
      text = Text(
        item.value,
        style: baseStyle.copyWith(color: explicitColor ?? defaultColor),
        // A dialog is a script-authored layout; wrapping is the script's business,
        // but overflowing the window would be worse than wrapping. The C renderer
        // draws a single clipped line; Flutter wrapping is the closer analogue of
        // "the text is visible" without pixel-clipping mid-glyph.
        softWrap: true,
      );
    }

    if (!hasIcon) {
      return text;
    }

    final ImageProvider? provider = imageProviderFor(
      classifyImageSource(item.image, baseDirectory: baseDirectory),
    );
    if (provider == null) {
      // `image_load` returned NULL: the item draws without its icon
      // (lib/script_dialog.c:200).
      return text;
    }

    // Icon box: explicit size, else the line height (C: `tm.tmHeight`).
    final double iconHeight = item.imageHeight > 0
        ? item.imageHeight.toDouble()
        : size;
    final double iconWidth = item.imageWidth > 0
        ? item.imageWidth.toDouble()
        : iconHeight;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: iconWidth,
          height: iconHeight,
          child: Image(image: provider, fit: BoxFit.contain),
        ),
        // C: `text_x += dw + 4`.
        const SizedBox(width: 4),
        Expanded(child: text),
      ],
    );
  }

  /// Pattern matching a leading field/key label followed by its value, e.g.
  /// "Status: Active" or "会话: session-1". Does not match a line that starts
  /// with a digit (a timestamp such as "12:30") or a URL (`https://…`, where the
  /// text after the colon starts with `//`).
  static final RegExp _kLabelValuePattern = RegExp(
    r'^([^\d:\n\r][^:\n\r]{0,31}[:：])(?!\s*//)(\s*)(.+)$',
  );

  /// Determine if a text item represents a standalone label or secondary caption.
  static bool _isLabel(DialogItem item) {
    final String trimmed = item.value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    // Items explicitly punctuated as a label or field key.
    if (trimmed.endsWith(':') || trimmed.endsWith('：')) {
      return true;
    }
    // Sub-10pt text is intentionally smaller than body size, serving as
    // secondary caption or footnote metadata.
    if (item.fontSize > 0 && item.fontSize < kDialogDefaultPointSize) {
      return true;
    }
    return false;
  }
}
