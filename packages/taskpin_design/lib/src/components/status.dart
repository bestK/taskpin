// Status components: StatusDot, StatusPill, IntervalBadge, RelativeTime,
// Sparkline.
//
// These are the "at a glance" vocabulary of a monitoring tool. Two rules
// govern all of them:
//
//   1. Colour means STATE. A green dot is green because the thing is healthy,
//      never because green looked nice.
//   2. Numbers are tabular. `TpRelativeTime` and `TpSparkline` axis labels both
//      go through `TpMetric` so a value ticking from 9 to 100 does not shove
//      its neighbours around.

import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/taskpin_theme.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'ui.dart';

/// A small coloured dot indicating state. Static; no animation.
class TpStatusDot extends StatelessWidget {
  const TpStatusDot({
    super.key,
    required this.kind,
    this.size = 8,
    this.pulsing = false,
    this.tooltip,
  });

  final TpStateKind kind;
  final double size;

  /// Accepted for source compatibility and ignored. Status is shown by colour
  /// and text, not by animation.
  final bool pulsing;

  /// Optional accessible label. A dot with no text is invisible to a screen
  /// reader, so callers should supply one whenever the dot carries meaning.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Widget dot = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.stateColor(kind),
          shape: BoxShape.circle,
        ),
      ),
    );
    if (tooltip == null) {
      return Semantics(label: kind.name, child: dot);
    }
    return Semantics(
      label: tooltip,
      child: Tooltip(message: tooltip!, child: dot),
    );
  }
}

/// A pill badge: a state dot plus a label, in the state's tinted fill.
class TpStatusPill extends StatelessWidget {
  const TpStatusPill({
    super.key,
    required this.label,
    required this.kind,
    this.showDot = true,
  });

  final String label;
  final TpStateKind kind;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color fg = theme.stateColor(kind);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.stateSubtle(kind),
        borderRadius: TpRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TpTypography.caption.toTextStyle().copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// A refresh-interval badge, e.g. `5s`, `30s`, `5m`.
///
/// The unit is rendered in tertiary text so a column of intervals scans by
/// magnitude rather than by digits.
class TpIntervalBadge extends StatelessWidget {
  const TpIntervalBadge({
    super.key,
    required this.interval,
    this.warning = false,
  });

  final Duration interval;

  /// Renders in warning colour. Used when an interval is fast enough to be a
  /// performance concern.
  final bool warning;

  /// Format a duration as the shortest exact unit: ms, s, m, h.
  ///
  /// Exposed as a static so `TpSignalGrid` and the diagnostics page render
  /// intervals identically.
  static String format(Duration d) {
    final int ms = d.inMilliseconds;
    if (ms < 1000) {
      return '$ms ms';
    }
    final int seconds = d.inSeconds;
    if (seconds < 60) {
      return '$seconds s';
    }
    final int minutes = d.inMinutes;
    if (minutes < 60) {
      final int rem = seconds % 60;
      return rem == 0 ? '$minutes m' : '$minutes m $rem s';
    }
    final int hours = d.inHours;
    final int rem = minutes % 60;
    return rem == 0 ? '$hours h' : '$hours h $rem m';
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Semantics(
      label: 'refresh interval ${format(interval)}',
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: hovered ? theme.bg.cardSecondary : Colors.transparent,
            borderRadius: TpRadius.chip,
            border: Border.all(color: theme.stroke.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                TpIcons.clock,
                size: 11,
                color: warning ? theme.status.caution : theme.text.tertiary,
              ),
              const SizedBox(width: 4),
              Text(
                format(interval),
                style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                      color: warning
                          ? theme.status.caution
                          : theme.text.secondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A relative timestamp: "just now", "12s ago", "3m ago", "2h ago".
///
/// Ticks itself so a stale card updates without the parent rebuilding.
class TpRelativeTime extends StatefulWidget {
  const TpRelativeTime({
    super.key,
    required this.timestamp,
    this.now,
    this.staleAfter,
    this.tick = const Duration(seconds: 1),
  });

  /// When the value was produced.
  final DateTime timestamp;

  /// Injectable clock. Tests pass a fixed value; the gallery passes null.
  final DateTime? now;

  /// Beyond this age the text renders in warning colour.
  final Duration? staleAfter;

  /// How often to re-render. Defaults to 1 s, which is right for a bar of
  /// second-resolution readouts.
  final Duration tick;

  /// Format the age. Pure and static so it can be unit-tested without a
  /// widget tree or a clock.
  static String formatAge(Duration age) {
    final int s = age.inSeconds;
    if (s < 1) {
      return 'just now';
    }
    if (s < 60) {
      return '${s}s ago';
    }
    final int m = age.inMinutes;
    if (m < 60) {
      return '${m}m ago';
    }
    final int h = age.inHours;
    if (h < 24) {
      return '${h}h ago';
    }
    return '${age.inDays}d ago';
  }

  @override
  State<TpRelativeTime> createState() => _TpRelativeTimeState();
}

class _TpRelativeTimeState extends State<TpRelativeTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TpRelativeTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) {
      _timer?.cancel();
      _start();
    }
  }

  void _start() {
    // A fixed clock means a test or a screenshot: do not tick.
    if (widget.now != null) {
      return;
    }
    _timer = Timer.periodic(widget.tick, (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final DateTime now = widget.now ?? DateTime.now();
    final Duration age = now.difference(widget.timestamp);

    final bool stale = widget.staleAfter != null && age > widget.staleAfter!;

    return Semantics(
      label: 'updated ${TpRelativeTime.formatAge(age)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (stale) ...<Widget>[
            Icon(TpIcons.warning, size: 12, color: theme.status.caution),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              TpRelativeTime.formatAge(age),
              overflow: TextOverflow.ellipsis,
              style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                    color: stale ? theme.status.caution : theme.text.tertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sparkline.
///
/// Rendered with a [CustomPainter] rather than a charting package: the
/// requirement is one line of history with no axes, no legend and no
/// interaction, and pulling in a chart library for that would be absurd.
///
/// When there are fewer than two points it renders a flat baseline instead of
/// nothing, so the slot does not collapse and shift the card's layout.
class TpSparkline extends StatelessWidget {
  const TpSparkline({
    super.key,
    required this.values,
    this.width = 80,
    this.height = 24,
    this.color,
    this.showArea = true,
    this.semanticsLabel,
  });

  /// The series, oldest first. Nulls are skipped.
  final List<double?> values;

  final double width;
  final double height;

  /// Defaults to the iris accent.
  final Color? color;

  /// Fill the area under the line with a faint gradient.
  final bool showArea;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color line = color ?? theme.accent.fill;

    return Semantics(
      label: semanticsLabel ?? 'sparkline',
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _TpSparklinePainter(
            values: values,
            color: line,
            showArea: showArea,
          ),
        ),
      ),
    );
  }
}

class _TpSparklinePainter extends CustomPainter {
  _TpSparklinePainter({
    required this.values,
    required this.color,
    required this.showArea,
  });

  final List<double?> values;
  final Color color;
  final bool showArea;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> points =
        values.whereType<double>().toList(growable: false);

    // Baseline when there is nothing to plot: keeps the slot's height stable.
    if (points.length < 2) {
      final Paint flat = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final double y = size.height - 1;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), flat);
      return;
    }

    double min = points.first;
    double max = points.first;
    for (final double p in points) {
      min = math.min(min, p);
      max = math.max(max, p);
    }
    // A flat series would divide by zero; give it a nominal range so it draws
    // a centred line rather than NaN.
    final double range = (max - min).abs() < 1e-9 ? 1.0 : (max - min);

    final double stepX = size.width / (points.length - 1);
    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = i * stepX;
      final double normalised = (points[i] - min) / range;
      final double y = size.height - (normalised * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (showArea) {
      final Path area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TpSparklinePainter old) =>
      old.color != color ||
      old.showArea != showArea ||
      !_listEquals(old.values, values);

  static bool _listEquals(List<double?> a, List<double?> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
