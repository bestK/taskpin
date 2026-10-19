// A real colour picker, in the Aurora idiom.
//
// The plan's fix for defect 3 is "真彩色选择器 + 正确标注格式" — a true-colour
// picker plus correctly labelled format. `ConfigColorField` owns the labelling
// and the BGR<->ARGB conversion; this file owns the picking, so a user never has
// to type a hex at all and therefore never has to reason about byte order.
//
// Why hand-rolled rather than a package: this app must not add a dependency it
// cannot resolve (the Flutter tool could not run in this environment, so no new
// package could be fetched), and the requirement is small and well-specified —
// hue + saturation/value + alpha, no eyedropper, no palette file, no colour
// space conversion. A `CustomPainter` is the honest implementation.
//
// Keyboard: the SV plane and the alpha strip are focusable and respond to arrow
// keys, per the package-wide rule that every interactive element is
// keyboard-operable. Escape closes; the popup is a `showDialog` so focus is
// trapped and the scrim matches the design system.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';
import 'config_color_field.dart';

/// The picker dialog.
class ColorPickerPopup extends StatefulWidget {
  const ColorPickerPopup({
    super.key,
    required this.initial,
    this.title,
  });

  /// The colour to start from.
  final Color initial;

  final String? title;

  /// Show the picker. Returns the chosen colour, or null when cancelled.
  static Future<Color?> show(
    BuildContext context, {
    required Color initial,
    String? title,
  }) {
    return showDialog<Color>(
      context: context,
      barrierColor: TaskPinTheme.of(context).smoke,
      builder: (BuildContext ctx) =>
          ColorPickerPopup(initial: initial, title: title),
    );
  }

  @override
  State<ColorPickerPopup> createState() => _ColorPickerPopupState();
}

class _ColorPickerPopupState extends State<ColorPickerPopup> {
  late HSVColor _hsv;
  late double _alpha;

  @override
  void initState() {
    super.initState();
    final HSVColor hsv = HSVColor.fromColor(widget.initial);
    // A fully desaturated or black colour has an undefined hue; starting at 0
    // would jump the marker to red the moment the user touches saturation, so
    // keep whatever hue came in (including 0) but remember saturation/value.
    _hsv = hsv;
    _alpha = ((widget.initial.toARGB32() >> 24) & 0xFF) / 255.0;
  }

  Color get _color => _hsv.withAlpha(_alpha).toColor();

  /// The stored value is BGR, so show the user the hex they will actually get.
  String get _diskHex => ConfigColorField.wireFromColor(_color);

  void _setHsv(HSVColor next) => setState(() => _hsv = next);

  void _nudge(double dh, double ds, double dv) {
    _setHsv(
      _hsv
          .withHue((_hsv.hue + dh) % 360)
          .withSaturation((_hsv.saturation + ds).clamp(0.0, 1.0))
          .withValue((_hsv.value + dv).clamp(0.0, 1.0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? title = widget.title;

    return Center(
      child: TpSurface(
        level: TpSurfaceLevel.dialog,
        radius: TpRadius.overlay,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(TpSpacing.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title ?? context.l10n.pickerTitle,
                  style: TpTypography.subtitle
                      .toTextStyle()
                      .copyWith(color: theme.text.primary),
                ),
                const SizedBox(height: TpSpacing.s16),

                // Saturation / value plane.
                _SvPlane(
                  hsv: _hsv,
                  onChanged: _setHsv,
                ),
                const SizedBox(height: TpSpacing.s12),

                // Hue.
                _HueStrip(
                  hue: _hsv.hue,
                  onChanged: (double h) => _setHsv(_hsv.withHue(h)),
                ),
                const SizedBox(height: TpSpacing.s12),

                // Alpha.
                _AlphaStrip(
                  alpha: _alpha,
                  color: _hsv.withAlpha(1).toColor(),
                  onChanged: (double a) => setState(() => _alpha = a),
                ),
                const SizedBox(height: TpSpacing.s16),

                // Preview + the on-disk value.
                Row(
                  children: <Widget>[
                    TpSurface(
                      level: TpSurfaceLevel.inset,
                      radius: TpRadius.control,
                      clip: true,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: ColoredBox(color: _color),
                      ),
                    ),
                    const SizedBox(width: TpSpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TpText(context.l10n.pickerStoredValue),
                          const SizedBox(height: TpSpacing.s4),
                          TpMetric(_diskHex),
                          const SizedBox(height: TpSpacing.s2),
                          Text(
                            context.l10n.pickerStoredHint,
                            style: TpTypography.caption
                                .toTextStyle()
                                .copyWith(color: theme.text.tertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TpSpacing.s20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TpButton(
                      label: context.l10n.editCancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: TpSpacing.s8),
                    TpButton(
                      label: context.l10n.pickerUse,
                      variant: TpButtonVariant.primary,
                      onPressed: () => Navigator.of(context).pop(_color),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The saturation (x) / value (y) plane for the current hue.
class _SvPlane extends StatelessWidget {
  const _SvPlane({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const double _height = 160;

  void _handle(Offset local, Size size) {
    final double s = (local.dx / size.width).clamp(0.0, 1.0);
    final double v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, _height);
        return _InteractiveSurface(
          semanticsLabel: context.l10n.pickerSaturation,
          onPointer: (Offset local) => _handle(local, size),
          onArrow: (int dx, int dy) => onChanged(
            hsv
                .withSaturation((hsv.saturation + dx * 0.02).clamp(0.0, 1.0))
                .withValue((hsv.value - dy * 0.02).clamp(0.0, 1.0)),
          ),
          child: SizedBox(
            height: _height,
            child: CustomPaint(
              painter: _SvPainter(hsv, TaskPinTheme.of(context)),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv, this.theme);

  final HSVColor hsv;
  final TaskPinTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    // White -> hue horizontally, then black vertically.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[Colors.white, hsv.withSaturation(1).withValue(1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );

    // Marker.
    final Offset p = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      p,
      7,
      Paint()
        ..color = theme.bg.window
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      p,
      8.5,
      Paint()
        ..color = theme.text.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hsv != hsv;
}

/// The hue rail.
class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const double _height = 18;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return _InteractiveSurface(
          semanticsLabel: context.l10n.pickerHue,
          onPointer: (Offset local) =>
              onChanged((local.dx / width).clamp(0.0, 1.0) * 360),
          onArrow: (int dx, int dy) =>
              onChanged((hue + dx * 4) % 360),
          child: SizedBox(
            height: _height,
            child: CustomPaint(
              painter: _HuePainter(hue, TaskPinTheme.of(context)),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue, this.theme);

  final double hue;
  final TaskPinTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final List<Color> colors = <Color>[
      for (int i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, (i * 60) % 360, 1, 1).toColor(),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );

    final double x = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, size.height / 2), width: 4, height: size.height + 4),
        const Radius.circular(2),
      ),
      Paint()
        ..color = theme.text.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// The alpha rail, drawn as a gradient of the current colour over a
/// checkerboard so "transparent" is legible.
class _AlphaStrip extends StatelessWidget {
  const _AlphaStrip({
    required this.alpha,
    required this.color,
    required this.onChanged,
  });

  final double alpha;
  final Color color;
  final ValueChanged<double> onChanged;

  static const double _height = 18;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return _InteractiveSurface(
          semanticsLabel: context.l10n.pickerOpacity,
          onPointer: (Offset local) =>
              onChanged((local.dx / width).clamp(0.0, 1.0)),
          onArrow: (int dx, int dy) =>
              onChanged((alpha + dx * 0.02).clamp(0.0, 1.0)),
          child: SizedBox(
            height: _height,
            child: CustomPaint(
              painter: _AlphaPainter(alpha, color, TaskPinTheme.of(context)),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.alpha, this.color, this.theme);

  final double alpha;
  final Color color;
  final TaskPinTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rr =
        RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Checkerboard.
    canvas.save();
    canvas.clipRRect(rr);
    const double cell = 6;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool even =
            ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          Paint()..color = even ? theme.bg.card : theme.bg.window,
        );
      }
    }
    canvas.restore();

    // Opaque -> transparent.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            color.withValues(alpha: 1),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    final double x = alpha * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(x, size.height / 2),
            width: 4,
            height: size.height + 4),
        const Radius.circular(2),
      ),
      Paint()
        ..color = theme.text.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter old) =>
      old.alpha != alpha || old.color != color;
}

/// Pointer + arrow-key handling shared by the three rails.
///
/// A `GestureDetector` alone would make the picker mouse-only, which the design
/// system forbids; `TpFocusRing` supplies the ring and Enter/Space, and this adds
/// arrow-key nudging and a semantics label.
class _InteractiveSurface extends StatelessWidget {
  const _InteractiveSurface({
    required this.child,
    required this.onPointer,
    required this.onArrow,
    required this.semanticsLabel,
  });

  final Widget child;

  /// Called with the local pointer position on tap or drag.
  final ValueChanged<Offset> onPointer;

  /// Called with a (-1/0/1, -1/0/1) delta for arrow keys.
  final void Function(int dx, int dy) onArrow;

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      slider: true,
      child: TpFocusRing(
        radius: TpRadius.control,
        onTap: () {},
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ArrowIntent: CallbackAction<_ArrowIntent>(
              onInvoke: (_ArrowIntent i) {
                onArrow(i.dx, i.dy);
                return null;
              },
            ),
          },
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowLeft): _ArrowIntent(-1, 0),
              SingleActivator(LogicalKeyboardKey.arrowRight): _ArrowIntent(1, 0),
              SingleActivator(LogicalKeyboardKey.arrowUp): _ArrowIntent(0, -1),
              SingleActivator(LogicalKeyboardKey.arrowDown): _ArrowIntent(0, 1),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails d) => onPointer(d.localPosition),
              onPanUpdate: (DragUpdateDetails d) =>
                  onPointer(d.localPosition),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowIntent extends Intent {
  const _ArrowIntent(this.dx, this.dy);
  final int dx;
  final int dy;
}
