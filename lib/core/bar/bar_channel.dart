// The Dart half of the `taskpin/bar` MethodChannel.
//
// This is the ONLY way a pinned item can appear in the real taskbar. Flutter
// cannot draw there: the bars are native child windows of `Shell_TrayWnd`,
// created by `native/win/bar_window.cpp` and driven over this channel. See
// docs/FLUTTER_REWRITE_PLAN.md ("Windows 任务栏条：原生 Direct2D 表面") for why
// reparenting a Flutter window into the taskbar is not viable.
//
// The native halves are
//   native/win/bar_channel.cpp   (Windows)
//   native/mac/...               (Phase 8; same contract, different painter)
// and they must stay argument-compatible with the method names below. That
// pairing is the contract.
//
// This file is deliberately free of Riverpod and of the engine: it is the wire,
// and nothing else. `bar_controller.dart` is what decides *what* to send.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// The channel name. Shared with every native implementation.
const String kBarChannel = 'taskpin/bar';

/// What a right-click on a bar chose.
///
/// The three ids are frozen by `native/win/bar_tokens.h`
/// (`kMenuUnpin`/`kMenuShow`/`kMenuExit`), and the C layer before it
/// (`lib/ui.h`) — the menu semantics must not drift.
enum BarMenuAction {
  unpin('unpin'),
  manage('manage'),
  exit('exit');

  const BarMenuAction(this.wireValue);

  final String wireValue;

  /// Parse the wire string. An unrecognised value is null: a menu id this
  /// build does not know about must not be silently treated as "unpin".
  static BarMenuAction? fromWire(String value) {
    for (final BarMenuAction a in BarMenuAction.values) {
      if (a.wireValue == value) {
        return a;
      }
    }
    return null;
  }
}

/// The visual state that drives the 2px left stripe.
///
/// Integer values match `native/win/bar_types.h` `ItemState` exactly.
enum BarItemState {
  none(0),
  running(1),
  error(2),
  stale(3);

  const BarItemState(this.wireValue);

  final int wireValue;

  static BarItemState fromWire(int value) {
    for (final BarItemState s in BarItemState.values) {
      if (s.wireValue == value) {
        return s;
      }
    }
    return BarItemState.none;
  }
}

/// One pinned item's visual configuration, as the native renderer wants it.
///
/// Colours are ARGB ints (`0xAARRGGBB`) because that is exactly what
/// `bar_tokens.h` stores and what `D2D1::ColorF` wants — so nothing is
/// reordered on the wire. This is the ONE place the BGR-hex confusion of
/// `config.json` must not leak: a value read from config goes through
/// `ConfigColor.colorrefToArgb` before it gets here.
class BarStyleSpec {
  const BarStyleSpec({
    this.background,
    this.backgroundHover,
    this.label,
    this.value,
    this.icon,
    this.fontSize = kBarDefaultFontSize,
    this.state = BarItemState.none,
    this.scrollEnabled = true,
    this.showSeparators = true,
  });

  /// `bar/bg`. Null = the frozen token default.
  final int? background;

  /// `bar/bgHover`.
  final int? backgroundHover;

  /// `bar/label`.
  final int? label;

  /// `bar/value`.
  final int? value;

  /// `bar/icon`.
  final int? icon;

  /// Point size, matching `cfg.font_size`. See [kBarDefaultFontSize].
  final int fontSize;

  final BarItemState state;

  final bool scrollEnabled;

  /// Whether the 1px vertical rules between segments are drawn.
  final bool showSeparators;

  Map<String, dynamic> toWire() => <String, dynamic>{
    if (background != null) 'bg': background,
    if (backgroundHover != null) 'bgHover': backgroundHover,
    if (label != null) 'label': label,
    if (value != null) 'value': value,
    if (icon != null) 'icon': icon,
    'fontSize': fontSize,
    'state': state.wireValue,
    'scrollEnabled': scrollEnabled,
    'showSeparators': showSeparators,
  };
}

/// The default bar text size, in POINTS.
///
/// 9, not 11. Three independent sources agree on 9 and the native renderer
/// already uses it:
///
///   * `lib/config.h:58` — `int font_size; /* point size, default 9 */`
///   * `lib/config.c:99` — `json_read_int(global, "font_size", 9)`
///   * `native/win/bar_types.h` — `int font_size = 9`
///
/// `TpBarTypography.labelSize` (11) is a DIP size for the Flutter PREVIEW
/// strip, and it is the outlier: 11 DIP == 8.25pt, so the preview was drawing
/// ~8% smaller than the taskbar. This constant is what the controller sends
/// when the config has no opinion, so the bar's own default is never silently
/// overridden by the preview's scale.
const int kBarDefaultFontSize = 9;

/// The wire encoding of one span.
///
/// Field names follow the engine's `TPSpan`, which [TpBarSpan] mirrors, so this
/// is a rename rather than a translation.
Map<String, dynamic> spanToWire(TpBarSpan span, {int? defaultFontSize}) {
  return <String, dynamic>{
    'text': span.text,
    if (span.color != null) 'color': span.color!.toARGB32(),
    'size': span.fontSize > 0 ? span.fontSize : (defaultFontSize ?? 0),
    'align': span.align.abiValue,
    'newline': span.newline,
    'image': span.isImage,
    'img_w': span.imageWidth,
    'img_h': span.imageHeight,
  };
}

/// Build the `spans` list for [content].
List<Map<String, dynamic>> contentToWire(
  TpBarContent content, {
  int? defaultFontSize,
}) =>
    content
        .clamped()
        .spans
        .map((TpBarSpan s) =>
            spanToWire(s, defaultFontSize: defaultFontSize))
        .toList(growable: false);

/// One native -> Dart event.
///
/// A single sealed-ish record rather than four callbacks, because the caller
/// has to route them all to the same place and a `switch` on a type is easier
/// to keep exhaustive than four nullable function fields.
sealed class BarEvent {
  const BarEvent(this.barId);

  /// The bar the event came from. `-1` for an app-wide event (Exit).
  final int barId;

  /// Decode one channel invocation. Returns null for a method this build does
  /// not know — a newer native side must not crash an older Dart side.
  static BarEvent? fromMethodCall(MethodCall call) {
    final Object? raw = call.arguments;
    final Map<Object?, Object?> args = raw is Map
        ? raw
        : const <Object?, Object?>{};
    final int barId = switch (args['barId']) {
      final int v => v,
      final num v => v.toInt(),
      _ => -1,
    };

    switch (call.method) {
      case 'onClick':
        return BarClickEvent(barId);
      case 'onWheel':
        return BarWheelEvent(
          barId,
          delta: _int(args['delta']),
          shift: args['shift'] == true,
          width: _int(args['width']),
          x: _int(args['x']),
        );
      case 'onContextMenu':
        final BarMenuAction? action = BarMenuAction.fromWire('${args['action']}');
        return action == null ? null : BarContextMenuEvent(barId, action);
      case 'onHoverChange':
        return BarHoverEvent(barId, hover: args['hover'] == true);
      default:
        return null;
    }
  }
}

/// Left click, or double click.
final class BarClickEvent extends BarEvent {
  const BarClickEvent(super.barId);
}

/// The wheel moved over a bar.
///
/// [delta] is 0 when this is a geometry-only report rather than a real wheel
/// turn — the native side reuses this event to tell Dart that its own wheel
/// handler already moved the bar, so Dart can persist the result without
/// fighting it.
final class BarWheelEvent extends BarEvent {
  const BarWheelEvent(
    super.barId, {
    required this.delta,
    required this.shift,
    required this.width,
    required this.x,
  });

  /// `GET_WHEEL_DELTA_WPARAM`: 120 per notch, sign gives the direction.
  final int delta;

  /// Shift was held, so this was a position change rather than a width change.
  final bool shift;

  /// The bar's width AFTER the change.
  final int width;

  /// The bar's x AFTER the change.
  final int x;
}

/// Right click, resolved to a menu choice.
final class BarContextMenuEvent extends BarEvent {
  const BarContextMenuEvent(super.barId, this.action);

  final BarMenuAction action;
}

/// The pointer entered or left a bar.
final class BarHoverEvent extends BarEvent {
  const BarHoverEvent(super.barId, {required this.hover});

  final bool hover;
}

/// The `taskpin/bar` wire.
///
/// Abstract so the controller can be tested without a native side, and so a
/// platform without an implementation degrades to "no bars" rather than to an
/// exception.
abstract class BarApi {
  /// Create or update one bar.
  ///
  /// Creates the native window and embeds it on the first call for a [barId];
  /// afterwards it only replaces the content. [width] is the configured width
  /// (0 = the native default); [x] of -1 means "auto: left of the tray".
  ///
  /// [autoIndex] is the ordering key for auto positioning: the item's index
  /// among the PINNED items, or -1 when the bar is explicitly positioned at
  /// [x]. Native sorts auto bars by it and re-tiles them as a set, so a
  /// reorder in the manager actually moves the taskbar bars. It is optional on
  /// the wire (native defaults it to -1) so the protocol stays compatible.
  Future<void> setSpans(
    int barId,
    List<Map<String, dynamic>> spans, {
    int width,
    int x,
    int autoIndex,
    String title,
  });

  /// Move and/or resize. Either may be -1 to leave it unchanged.
  ///
  /// [autoIndex] has the same meaning as in [setSpans]; sending it again is
  /// what re-tiles the bars after a reorder or a pin/unpin.
  ///
  /// Does NOT persist: the caller owns persistence, because only it knows
  /// which `PinItem` the bar belongs to.
  Future<void> setGeometry(int barId, {int width, int x, int autoIndex});

  /// Replace the style.
  Future<void> setStyle(int barId, BarStyleSpec style);

  /// Tear one bar down.
  Future<void> remove(int barId);

  /// Tear every bar down.
  Future<void> removeAll();

  /// Re-parent every bar into the taskbar, after an explorer restart.
  Future<void> reembedAll();

  /// Events from the native side.
  Stream<BarEvent> get events;
}

/// The real implementation, over [kBarChannel].
class MethodChannelBarApi implements BarApi {
  MethodChannelBarApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kBarChannel) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<BarEvent> _events =
      StreamController<BarEvent>.broadcast();

  /// Invoked when a native call could not be applied. Null = ignore.
  void Function(String method, String reason)? onError;

  Future<void> _onCall(MethodCall call) async {
    final BarEvent? event = BarEvent.fromMethodCall(call);
    if (event != null) {
      _events.add(event);
    }
    return null;
  }

  /// Swallow platform errors, exactly as `MethodChannelDialogWindowApi` does.
  ///
  /// A bar that cannot reach the native side must not take the manager window
  /// down with it: the app is still usable, the item just does not appear in
  /// the taskbar. The failure is reported through [onError] rather than
  /// dropped.
  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      onError?.call(method, 'no native implementation');
    } on PlatformException catch (e) {
      onError?.call(method, e.message ?? e.code);
    }
  }

  @override
  Future<void> setSpans(
    int barId,
    List<Map<String, dynamic>> spans, {
    int width = 0,
    int x = -1,
    int autoIndex = -1,
    String title = '',
  }) => _invoke('setSpans', <String, dynamic>{
    'barId': barId,
    'spans': spans,
    'width': width,
    'x': x,
    'autoIndex': autoIndex,
    'title': title,
  });

  @override
  Future<void> setGeometry(
    int barId, {
    int width = -1,
    int x = -1,
    int autoIndex = -1,
  }) => _invoke('setGeometry', <String, dynamic>{
    'barId': barId,
    'width': width,
    'x': x,
    'autoIndex': autoIndex,
  });

  @override
  Future<void> setStyle(int barId, BarStyleSpec style) => _invoke('setStyle', <
      String, dynamic>{'barId': barId, ...style.toWire()});

  @override
  Future<void> remove(int barId) =>
      _invoke('remove', <String, dynamic>{'barId': barId});

  @override
  Future<void> removeAll() => _invoke('removeAll');

  @override
  Future<void> reembedAll() => _invoke('reembedAll');

  @override
  Stream<BarEvent> get events => _events.stream;

  /// Release the channel handler and the event stream.
  Future<void> dispose() async {
    // `setMethodCallHandler` returns void, not a Future.
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}

/// A no-op implementation, for tests and for platforms with no native half.
class NoopBarApi implements BarApi {
  const NoopBarApi();

  @override
  Future<void> setSpans(
    int barId,
    List<Map<String, dynamic>> spans, {
    int width = 0,
    int x = -1,
    int autoIndex = -1,
    String title = '',
  }) async {}
  @override
  Future<void> setGeometry(
    int barId, {
    int width = -1,
    int x = -1,
    int autoIndex = -1,
  }) async {}
  @override
  Future<void> setStyle(int barId, BarStyleSpec style) async {}
  @override
  Future<void> remove(int barId) async {}
  @override
  Future<void> removeAll() async {}
  @override
  Future<void> reembedAll() async {}
  @override
  Stream<BarEvent> get events => const Stream<BarEvent>.empty();
}

/// Records calls instead of applying them. Test seam.
class RecordingBarApi implements BarApi {
  final List<String> calls = <String>[];

  /// The last style sent per bar, so a test can assert on colours rather than
  /// on a formatted string.
  final Map<int, BarStyleSpec> styles = <int, BarStyleSpec>{};

  final StreamController<BarEvent> _events =
      StreamController<BarEvent>.broadcast();

  /// Push an event as if the native side had sent it.
  void emit(BarEvent event) => _events.add(event);

  @override
  Future<void> setSpans(
    int barId,
    List<Map<String, dynamic>> spans, {
    int width = 0,
    int x = -1,
    int autoIndex = -1,
    String title = '',
  }) async => calls.add(
    'setSpans($barId,w=$width,x=$x,a=$autoIndex,n=${spans.length})',
  );

  @override
  Future<void> setGeometry(
    int barId, {
    int width = -1,
    int x = -1,
    int autoIndex = -1,
  }) async => calls.add('setGeometry($barId,$width,$x,a=$autoIndex)');

  @override
  Future<void> setStyle(int barId, BarStyleSpec style) async {
    styles[barId] = style;
    calls.add('setStyle($barId,${style.state.wireValue})');
  }

  @override
  Future<void> remove(int barId) async => calls.add('remove($barId)');

  @override
  Future<void> removeAll() async => calls.add('removeAll');

  @override
  Future<void> reembedAll() async => calls.add('reembedAll');

  @override
  Stream<BarEvent> get events => _events.stream;

  Future<void> dispose() => _events.close();
}

/// Whether this platform has a native bar implementation.
bool get platformHasBars => Platform.isWindows || Platform.isMacOS;

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return 0;
}
