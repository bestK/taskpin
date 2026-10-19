// A `DI_IMG` item — a standalone image block.
//
// C parity (`lib/script_dialog.c:311-328`):
//   - box is `img_w`/`img_h`, each defaulting to 64 (`:313-314`);
//   - the image is drawn at that box, top-left aligned, and the item advances
//     by the drawn height;
//   - a source that fails to load draws NOTHING and does not advance
//     (`:316, :326`).
//
// The last point is why a null provider collapses to `SizedBox.shrink()` rather
// than a placeholder box: an unloadable image must not leave a 64 px hole.

import 'package:flutter/widgets.dart';

import '../dialog_spec.dart';
import '../image_source.dart';

class DialogImageItem extends StatelessWidget {
  const DialogImageItem({super.key, required this.item, this.baseDirectory});

  final DialogItem item;

  /// Resolved against a relative `image` source, when the caller has one.
  final String? baseDirectory;

  /// The C default box when the script specifies no size
  /// (`lib/script_dialog.c:313-314`).
  static const double defaultSize = 64;

  @override
  Widget build(BuildContext context) {
    if (item.image.isEmpty) {
      // C: `if (!item->img_source[0]) break;` (`:312`).
      return const SizedBox.shrink();
    }

    final ImageProvider? provider = imageProviderFor(
      classifyImageSource(item.image, baseDirectory: baseDirectory),
    );
    if (provider == null) {
      // `image_load` returned NULL: nothing is drawn and the item does not
      // advance (`:316-327`).
      return const SizedBox.shrink();
    }

    final double w = item.imageWidth > 0
        ? item.imageWidth.toDouble()
        : defaultSize;
    final double h = item.imageHeight > 0
        ? item.imageHeight.toDouble()
        : defaultSize;

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: w,
        height: h,
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          // A failed network fetch must not throw inside the dialog's isolate.
          errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
              const SizedBox.shrink(),
        ),
      ),
    );
  }
}
