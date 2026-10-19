// A `webview` item — the one item type the engine CARRIES but does not render.
//
// `TP_DIALOG_TYPE_WEBVIEW` is defined in `native/engine/taskpin_engine.h` with
// the comment "carried only: the engine parses the item and passes url/width/
// height through so the Flutter UI can render it. WebView2 embedding is Phase 9
// of the rewrite plan and lives in native/win, not here."
//
// So this phase renders an honest placeholder — the URL, the requested box, and
// the Shift+drag hint a borderless webview dialog needs — and Phase 9 replaces
// this widget with the real host (`lib/features/dialogs/webview_item.dart` is
// that phase's file per the plan, so the swap is local).
//
// Deliberately NOT adding `webview_flutter`: it is not in the pub cache, the
// plan puts WebView2 in `native/win/webview2_host.cpp`, and a Dart-side webview
// would be a third implementation rather than the one the plan calls for.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_spec.dart';

class DialogWebviewItem extends StatelessWidget {
  const DialogWebviewItem({
    super.key,
    required this.item,
    required this.borderless,
  });

  final DialogItem item;

  /// A borderless dialog needs the drag affordance spelled out, which is what
  /// `webview.drag_hint` exists for.
  final bool borderless;

  /// The fallback box when the script sends no size. The ABI carries `web_w` /
  /// `web_h`; a webview with neither is unbounded, so this keeps the item
  /// visible instead of collapsing it to zero height.
  static const double defaultWidth = 480;
  static const double defaultHeight = 320;

  /// `webview.drag_hint` from `lang/en-US.json` (`webviewDragHint` in the ARB).
  ///
  /// Inlined rather than read from `AppLocalizations` because Phase 0 has not
  /// generated that class yet (`lib/l10n/` holds only the two `.arb` files).
  /// When it lands, this constant and the one below are the only edits.
  static const String dragHint = 'Shift + Drag / Scroll';

  /// `webview.err_no_runtime` from `lang/en-US.json` (`webviewErrNoRuntime`).
  static const String notAvailable = '[WebView not available]';

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final double w = item.webWidth > 0
        ? item.webWidth.toDouble()
        : defaultWidth;
    final double h = item.webHeight > 0
        ? item.webHeight.toDouble()
        : defaultHeight;

    return SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.bg.cardSecondary,
          borderRadius: TpRadius.control,
          border: Border.all(color: theme.stroke.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TpSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(TpIcons.info, size: 16, color: theme.text.tertiary),
                  const SizedBox(width: TpSpacing.s8),
                  Expanded(
                    child: Text(
                      notAvailable,
                      style: TpTypography.body.toTextStyle().copyWith(
                        color: theme.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TpSpacing.s8),
              Text(
                item.url,
                style: TpTypography.caption.toTextStyle().copyWith(
                  color: theme.text.tertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: TpSpacing.s8),
              Text(
                'WebView2 embedding lands in Phase 9 (native/win/webview2_host.cpp).',
                style: TpTypography.caption.toTextStyle().copyWith(
                  color: theme.text.disabled,
                ),
              ),
              if (borderless) ...<Widget>[
                const SizedBox(height: TpSpacing.s8),
                Text(
                  dragHint,
                  style: TpTypography.caption.toTextStyle().copyWith(
                    color: theme.text.tertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
