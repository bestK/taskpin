// Motion durations, curves and the reduced-motion contract (docs/VISUAL_SPEC.md §3.5).
//
// Components must call [resolve] or [resolveCurve] so that
// `MediaQuery.disableAnimations` is honoured.

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show TickerProvider;
import 'package:flutter/widgets.dart';

/// Motion scale.
class TpMotion {
  const TpMotion._();

  /// Hover and press colour changes.
  static const Duration fast = Duration(milliseconds: 83);

  /// Expand, fade.
  static const Duration base = Duration(milliseconds: 167);

  /// Page transitions and dialogs.
  static const Duration slow = Duration(milliseconds: 250);

  /// Stage entrance: a block rising into place.
  static const Duration entrance = Duration(milliseconds: 900);

  /// Delay between consecutive rows in a staggered entrance.
  static const Duration stagger = Duration(milliseconds: 60);

  /// The spotlight's one slow sweep across the stage on open.
  static const Duration drift = Duration(milliseconds: 9000);

  /// Colour changes use a linear curve.
  static const Curve linear = Curves.linear;

  /// Expand and fade.
  static const Curve standard = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Page transitions and dialogs. Same curve as [standard].
  static const Curve decelerate = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Stage entrance: fast start, long soft landing. CSS cubic-bezier(.2,.8,.2,1).
  static const Curve stage = Cubic(0.2, 0.8, 0.2, 1.0);

  /// Toggle knob: overshoots and settles. CSS cubic-bezier(.3,1.4,.5,1).
  static const Curve spring = Cubic(0.3, 1.4, 0.5, 1.0);

  /// Whether the platform has asked for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Collapse a duration to zero when reduced motion is requested.
  static Duration resolve(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Collapse a curve to linear when reduced motion is requested.
  static Curve resolveCurve(BuildContext context, Curve curve) =>
      reduced(context) ? Curves.linear : curve;

  /// An [AnimationController] whose duration respects reduced motion.
  static AnimationController controller(
    TickerProvider vsync, {
    required BuildContext context,
    required Duration duration,
    double value = 0.0,
  }) =>
      AnimationController(
        vsync: vsync,
        duration: resolve(context, duration),
        value: value,
      );
}
