// Bar-specific components: BarPreviewStrip, SpanInspector, DialogSpecPreview.
//
// The point of `TpBarPreviewStrip` is stated in the plan: render the SAME span
// model in the management window that the native renderer will draw in the
// taskbar, so you can see what you are pinning before you pin it.
//
// It therefore does not use the app type scale. It uses `TpBarMetrics` and
// `TpBarTypography`, the frozen numbers the C++ and Swift renderers also use.
// If the preview looks right and the bar looks wrong, the two token files have
// drifted — which is exactly the failure this widget is designed to surface.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/bar_span.dart';
import '../theme/taskpin_theme.dart';
import '../tokens/bar_tokens.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/color_hex.dart';
import '../util/focus.dart';
import 'data.dart';
import 'forms.dart';
import 'ui.dart';

/// The state the bar is in, which selects the state strip colour.
enum TpBarState {
  /// Healthy. Transparent strip — health is the absence of a signal.
  running,

  /// A Lua error or a failed fetch.
  error,

  /// `now - lastUpdate > 2 x interval`.
  stale,

  /// A fetch is in flight.
  loading,
}

/// A faithful preview of one bar item.
class TpBarPreviewStrip extends StatelessWidget {
  const TpBarPreviewStrip({
    super.key,
    required this.content,
    this.state = TpBarState.running,
    this.platform = TpBarPlatform.windows,
    this.background,
    this.hovered = false,
    this.width,
    this.height,
    this.showStateStrip = true,
    this.showSeparators = true,
  });

  /// The spans to render. The same model the native renderer consumes.
  final TpBarContent content;

  final TpBarState state;
  final TpBarPlatform platform;

  /// Item background override, from `bar_bg_color` in config.json.
  final Color? background;

  /// Whether to draw the hover treatment (fill + hairline).
  final bool hovered;

  /// Fixed width. Null sizes to the content, which is what you want in a form.
  final double? width;

  /// Height override. Null uses the platform bar height. Used by the compact
  /// 36 px strips inside project and market cards.
  final double? height;

  final bool showStateStrip;
  final bool showSeparators;

  /// The colour for the state strip.
  static Color stateColor(TpBarState state) {
    switch (state) {
      case TpBarState.running:
        return TpBarColors.stateRunning;
      case TpBarState.error:
        return TpBarColors.stateError;
      case TpBarState.stale:
        return TpBarColors.stateStale;
      case TpBarState.loading:
        return TpBarColors.stateRunning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TpBarMetrics m = TpBarMetrics.of(platform);
    final List<List<TpBarSpan>> lines = content.lines;
    final double stripHeight = height ?? m.height;
    final double available = stripHeight - m.padVertical * 2;
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    // The compact strips inside cards are 36 high, leaving 24 px for content.
    // Two 11 px lines at 1.25 do not fit there, so show the first line only
    // rather than overflowing. Lines are dropped from the end, which keeps the
    // primary reading.
    final List<List<TpBarSpan>> visible = <List<TpBarSpan>>[];
    double used = 0;
    if (available > 0) {
      for (final List<TpBarSpan> line in lines.take(m.maxLines)) {
        final double lineHeight = _lineHeight(line, m, scaler);
        if (visible.isNotEmpty && used + lineHeight > available) break;
        visible.add(line);
        used += lineHeight;
      }
    }

    // A single line can still be taller than the strip (a large font size or
    // 150 % text scaling). Clamp its line height to what is available.
    double? heightMultiplier;
    if (visible.length == 1 && used > available && available > 0) {
      final double maxSize = _maxFontSize(visible.first, m);
      if (maxSize > 0) {
        heightMultiplier = available / scaler.scale(maxSize);
      }
    }

    // The state strip occupies the far left, full height.
    final double stripWidth = showStateStrip ? m.stateStripWidth : 0;

    Widget body = Padding(
      padding: EdgeInsets.fromLTRB(
        stripWidth + m.padHorizontal,
        m.padVertical,
        m.padHorizontal,
        m.padVertical,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final List<TpBarSpan> line in visible)
            _line(context, line, m, heightMultiplier),
        ],
      ),
    );

    // Loading dims the whole strip; the shimmer is a separate concern the
    // native renderer implements, but the opacity matches.
    if (state == TpBarState.loading) {
      body = Opacity(opacity: TpBarTypography.loadingOpacity, child: body);
    }

    return Container(
      width: width,
      height: height ?? m.height,
      decoration: BoxDecoration(
        color: background ??
            (hovered ? TpBarColors.bgHover : TpBarColors.bg),
        borderRadius: BorderRadius.circular(m.radius),
        border: hovered
            ? Border.symmetric(
                horizontal: BorderSide(color: TpBarColors.hairline),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showStateStrip)
            Container(
              width: m.stateStripWidth,
              color: stateColor(state),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  /// Line height in logical pixels, matching what [_span] renders.
  double _lineHeight(List<TpBarSpan> spans, TpBarMetrics m, TextScaler scaler) =>
      scaler.scale(_maxFontSize(spans, m)) * TpBarTypography.lineHeightMultiplier;

  /// The largest font size on [spans]; the default when none sets one.
  double _maxFontSize(List<TpBarSpan> spans, TpBarMetrics m) {
    double size = TpBarTypography.labelSize;
    for (final TpBarSpan span in spans) {
      if (!span.isImage && span.fontSize > 0) {
        size = span.fontSize > size ? span.fontSize.toDouble() : size;
      }
    }
    return size;
  }

  Widget _line(
    BuildContext context,
    List<TpBarSpan> spans,
    TpBarMetrics m,
    double? heightMultiplier,
  ) {
    final List<Widget> children = <Widget>[];

    for (int i = 0; i < spans.length; i++) {
      final TpBarSpan span = spans[i];

      // A separator between adjacent segments, not before the first one. This
      // is the rule the plan calls the key to making a run of coloured text
      // readable as a set of readings.
      if (showSeparators && i > 0) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.separatorGap),
            child: Container(
              width: m.separatorWidth,
              height: m.separatorHeight,
              color: TpBarColors.separator,
            ),
          ),
        );
      }

      children.add(_span(context, span, m, heightMultiplier));
    }

    // A horizontal scroll view with scrolling disabled clips a line that is
    // wider than the strip, which is what the native renderer does. Without
    // it a long reading reports a horizontal RenderFlex overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _span(
    BuildContext context,
    TpBarSpan span,
    TpBarMetrics m,
    double? heightMultiplier,
  ) {
    if (span.isImage) {
      // The preview cannot resolve the script's image sources (that is the
      // engine's job), so it draws the icon slot at the correct size. This
      // keeps the layout honest even when the pixels are not available.
      return Padding(
        padding: const EdgeInsets.only(right: TpSpacing.s6),
        child: SizedBox(
          width: (span.imageWidth > 0 ? span.imageWidth : m.iconSize)
              .toDouble(),
          height: (span.imageHeight > 0 ? span.imageHeight : m.iconSize)
              .toDouble(),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: TpBarColors.icon,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      );
    }

    final double size = span.fontSize > 0
        ? span.fontSize.toDouble()
        : TpBarTypography.labelSize;

    return Text(
      span.text,
      style: TextStyle(
        // The bar uses the system font, never Inter.
        fontFamily: m.platform == TpBarPlatform.windows
            ? TpBarTypography.windowsFamily
            : TpBarTypography.macOSFamily,
        fontSize: size,
        height: heightMultiplier ?? TpBarTypography.lineHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: span.color ?? TpBarColors.value,
        // Tabular, always. This is the rule that stops a value changing width
        // from shifting every segment to its right.
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Per-span override editor.
///
/// The plan's requirement: "逐 span 覆盖颜色/字号/对齐". One row per span, each
/// with the override controls the native renderer honours.
class TpSpanInspector extends StatelessWidget {
  const TpSpanInspector({
    super.key,
    required this.spans,
    required this.onChanged,
    this.enabled = true,
  });

  final List<TpBarSpan> spans;

  /// Called with the full replacement list whenever any span changes.
  final ValueChanged<List<TpBarSpan>> onChanged;

  final bool enabled;

  void _replace(int index, TpBarSpan next) {
    final List<TpBarSpan> copy = List<TpBarSpan>.of(spans);
    copy[index] = next;
    onChanged(copy);
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    if (spans.isEmpty) {
      return TpSurface(
        level: TpSurfaceLevel.inset,
        padding: const EdgeInsets.all(TpSpacing.s16),
        child: Text(
          'This script returns no spans.',
          style: TpTypography.caption
              .toTextStyle()
              .copyWith(color: theme.text.tertiary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < spans.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: TpSpacing.s12),
          _TpSpanRow(
            index: i,
            span: spans[i],
            enabled: enabled,
            onChanged: (TpBarSpan next) => _replace(i, next),
          ),
        ],
      ],
    );
  }
}

class _TpSpanRow extends StatelessWidget {
  const _TpSpanRow({
    required this.index,
    required this.span,
    required this.onChanged,
    this.enabled = true,
  });

  final int index;
  final TpBarSpan span;
  final ValueChanged<TpBarSpan> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color? override = span.color;

    return TpSurface(
      level: TpSurfaceLevel.card,
      padding: const EdgeInsets.all(TpSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              TpText('Span ${index + 1}'),
              const SizedBox(width: TpSpacing.s8),
              if (span.isImage) const TpSourceChip(label: 'image'),
              const Spacer(),
              // Live preview of the override, using the bar's own colours.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpSpacing.s8,
                  vertical: TpSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: TpBarColors.bg,
                  borderRadius: TpRadius.chip,
                  border: Border.all(color: theme.stroke.divider),
                ),
                child: Text(
                  span.isImage ? '[image]' : span.text,
                  style: TextStyle(
                    fontFamily: TpBarTypography.windowsFamily,
                    fontSize: TpBarTypography.labelSize,
                    color: override ?? TpBarColors.label,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: TpSelect<TpSpanAlign>(
                  label: 'Align',
                  value: span.align,
                  enabled: enabled,
                  items: const <TpSelectItem<TpSpanAlign>>[
                    TpSelectItem<TpSpanAlign>(
                      value: TpSpanAlign.left,
                      label: 'Left',
                    ),
                    TpSelectItem<TpSpanAlign>(
                      value: TpSpanAlign.right,
                      label: 'Right',
                    ),
                    TpSelectItem<TpSpanAlign>(
                      value: TpSpanAlign.center,
                      label: 'Center',
                    ),
                  ],
                  onChanged: (TpSpanAlign? v) {
                    if (v != null) {
                      onChanged(span.copyWith(align: v));
                    }
                  },
                ),
              ),
              const SizedBox(width: TpSpacing.s12),
              SizedBox(
                width: 120,
                child: TpNumberField(
                  value: span.fontSize == 0 ? null : span.fontSize,
                  label: 'Size',
                  enabled: enabled,
                  min: 0,
                  max: 32,
                  onChanged: (num? v) =>
                      onChanged(span.copyWith(fontSize: v?.round() ?? 0)),
                ),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: TpColorField(
                  // `TpColorField` speaks the config's AARRGGBB wire format.
                  wireValue: span.color == null
                      ? kColorInherit
                      : TpColorHex.toWire(span.color!),
                  label: 'Colour override',
                  enabled: enabled,
                  onChanged: (String wire) {
                    if (TpColorHex.isInherit(wire)) {
                      onChanged(span.copyWith(clearColor: true));
                      return;
                    }
                    final Color? parsed = TpColorHex.fromWire(wire);
                    onChanged(
                      parsed == null
                          ? span.copyWith(clearColor: true)
                          : span.copyWith(color: parsed),
                    );
                  },
                ),
              ),
              const SizedBox(width: TpSpacing.s16),
              TpSwitch(
                value: span.newline,
                label: 'New line',
                enabled: enabled,
                onChanged: (bool v) => onChanged(span.copyWith(newline: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A preview of a `DialogSpec` before it is shown.
///
/// Deliberately schematic: it renders the item TYPES and their content in a
/// box of the configured size, so the user can check the structure (a table
/// with the right columns, an image with the right aspect) without the real
/// dialog being spawned. The real rendering lives in `lib/features/dialogs`.
class TpDialogSpecPreview extends StatelessWidget {
  const TpDialogSpecPreview({
    super.key,
    required this.items,
    this.width = 320,
    this.height = 200,
    this.title,
  });

  /// The dialog items, in order.
  final List<TpDialogSpecItem> items;

  /// The configured dialog size (`dlg_w` / `dlg_h` in config.json).
  final double width;
  final double height;

  final String? title;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? t = title;

    return TpSurface(
      level: TpSurfaceLevel.flyout,
      radius: TpRadius.overlay,
      clip: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (t != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpSpacing.s12,
                  vertical: TpSpacing.s8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.stroke.divider),
                  ),
                ),
                child: Text(
                  t,
                  style: TpTypography.body
                      .toTextStyle()
                      .copyWith(color: theme.text.secondary),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TpSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < items.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: TpSpacing.s8),
                      _item(context, items[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, TpDialogSpecItem item) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    switch (item.type) {
      case TpDialogItemType.text:
        return Text(
          item.text ?? '',
          style: TpTypography.body
              .toTextStyle()
              .copyWith(color: theme.text.primary),
        );
      case TpDialogItemType.hr:
        return const TpDivider();
      case TpDialogItemType.image:
        return TpSurface(
          level: TpSurfaceLevel.inset,
          radius: TpRadius.control,
          child: SizedBox(
            height: 64,
            child: Center(
              child: Text(
                item.text ?? 'image',
                style: TpTypography.caption
                    .toTextStyle()
                    .copyWith(color: theme.text.tertiary),
              ),
            ),
          ),
        );
      case TpDialogItemType.table:
        return _table(context, item);
      case TpDialogItemType.button:
        return Align(
          alignment: Alignment.centerLeft,
          child: TpSurface(
            level: TpSurfaceLevel.inset,
            radius: TpRadius.control,
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s12,
              vertical: TpSpacing.s6,
            ),
            child: Text(
              item.text ?? 'button',
              style: TpTypography.body
                  .toTextStyle()
                  .copyWith(color: theme.text.primary),
            ),
          ),
        );
    }
  }

  Widget _table(BuildContext context, TpDialogSpecItem item) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<List<String>> rows = item.rows ?? const <List<String>>[];
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return TpSurface(
      level: TpSurfaceLevel.inset,
      radius: TpRadius.control,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int r = 0; r < rows.length; r++) ...<Widget>[
            if (r > 0) const TpDivider(),
            Container(
              color: r == 0 ? theme.bg.window : null,
              padding: const EdgeInsets.symmetric(
                horizontal: TpSpacing.s8,
                vertical: TpSpacing.s6,
              ),
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < rows[r].length; c++)
                    Expanded(
                      child: Text(
                        rows[r][c],
                        style: (r == 0
                                ? TpTypography.caption
                                : TpTypography.caption)
                            .toTextStyle()
                            .copyWith(
                              color: r == 0
                                  ? theme.text.tertiary
                                  : theme.text.primary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The kinds of item a dialog spec can contain.
///
/// Mirrors `DI_TEXT | DI_HR | DI_TABLE | DI_IMG | DI_BUTTON` from the C side.
enum TpDialogItemType { text, hr, table, image, button }

/// One item in a dialog spec.
class TpDialogSpecItem {
  const TpDialogSpecItem({
    required this.type,
    this.text,
    this.rows,
    this.width,
    this.height,
    this.url,
    this.cmd,
  });

  final TpDialogItemType type;
  final String? text;

  /// Table rows. Row 0 is the header.
  final List<List<String>>? rows;

  /// Image dimensions.
  final int? width;
  final int? height;

  /// Per-row navigation: a URL to open.
  final String? url;

  /// Per-row action: a command to run.
  final String? cmd;
}

/// One item presented in the simulated taskbar flight strip.
class TpTaskbarFlightStripItem {
  const TpTaskbarFlightStripItem({
    required this.name,
    this.spans = const <TpBarSpan>[],
    this.pinned = false,
    this.state = TpBarState.running,
    this.background,
    this.width,
    this.itemIndex,
    this.subtitle,
  });

  /// The label or title of the signal.
  final String name;

  /// Rendered text spans for the widget.
  final List<TpBarSpan> spans;

  /// Whether this signal is pinned to the taskbar.
  final bool pinned;

  /// Operational state (running, error, stale, loading).
  final TpBarState state;

  /// Background color override.
  final Color? background;

  /// Custom bar width.
  final double? width;

  /// Index of the item in the configuration.
  final int? itemIndex;

  /// Optional subtitle or file source.
  final String? subtitle;
}

/// The signature Live Taskbar Flight Strip component.
///
/// Simulates the physical Windows taskbar (or macOS menu bar) environment in
/// real time. Shows all active pinned signals side-by-side with genuine segment
/// dividers, authentic taskbar dimensions, hover states, and direct click-to-edit
/// navigation, flanked by a simulated OS system tray.
class TpTaskbarFlightStrip extends StatelessWidget {
  const TpTaskbarFlightStrip({
    super.key,
    required this.items,
    this.selectedIndex,
    this.onSelectItem,
    this.platform = TpBarPlatform.windows,
    this.mockTime = '17:28',
    this.slotLimit = 16,
    this.compact = false,
  });

  /// All signals available or configured in the system.
  final List<TpTaskbarFlightStripItem> items;

  /// The index of the currently selected / edited signal.
  final int? selectedIndex;

  /// Callback when a taskbar widget segment is clicked.
  final ValueChanged<int>? onSelectItem;

  /// The target OS shell environment.
  final TpBarPlatform platform;

  /// Clock text for the simulated system tray.
  final String mockTime;

  /// Maximum slots allowed by the native bar engine (default 16).
  final int slotLimit;

  /// Compact mode for tight spaces.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<TpTaskbarFlightStripItem> pinnedItems =
        items.where((TpTaskbarFlightStripItem it) => it.pinned).toList();
    final int pinnedCount = pinnedItems.length;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.bg.card,
        border: Border(
          top: BorderSide(color: theme.control.strokeStrong.withValues(alpha: 0.6)),
          bottom: BorderSide(color: theme.stroke.divider),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Left Dock Badge: Flight Deck Identifier
          _buildDockBadge(context, theme, pinnedCount),

          // Center Pinned Segment Bay
          Expanded(
            child: pinnedItems.isEmpty
                ? _buildEmptyPrompt(theme)
                : _buildPinnedItemsList(context, theme, pinnedItems),
          ),

          // Right Simulated OS System Tray
          _buildSystemTray(theme, pinnedCount),
        ],
      ),
    );
  }

  Widget _buildDockBadge(
    BuildContext context,
    TaskPinTheme theme,
    int pinnedCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.stroke.divider),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pinnedCount > 0 ? theme.status.success : theme.status.neutral,
              boxShadow: pinnedCount > 0
                  ? <BoxShadow>[
                      BoxShadow(
                        color: theme.status.success.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: TpSpacing.s8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'TASKBAR DOCK',
                    style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                          color: theme.text.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                  ),
                  const SizedBox(width: TpSpacing.s4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpSpacing.s4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.subtle.hover,
                      borderRadius: TpRadius.chip,
                    ),
                    child: Text(
                      'LIVE',
                      style: TpTypography.caption.toTextStyle().copyWith(
                            color: theme.accent.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              Text(
                'Direct2D Layer',
                style: TpTypography.caption.toTextStyle().copyWith(
                      color: theme.text.tertiary,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPrompt(TaskPinTheme theme) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            TpIcons.pin,
            size: 13,
            color: theme.text.tertiary,
          ),
          const SizedBox(width: TpSpacing.s6),
          Flexible(
            child: Text(
              'Taskbar empty — toggle Pin on any signal to mount here',
              overflow: TextOverflow.ellipsis,
              style: TpTypography.caption.toTextStyle().copyWith(
                    color: theme.text.tertiary,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedItemsList(
    BuildContext context,
    TaskPinTheme theme,
    List<TpTaskbarFlightStripItem> pinnedList,
  ) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: pinnedList.length,
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
      itemBuilder: (BuildContext context, int i) {
        final TpTaskbarFlightStripItem it = pinnedList[i];
        final bool isSelected =
            it.itemIndex != null && it.itemIndex == selectedIndex;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TpSpacing.s4,
            vertical: TpSpacing.s6,
          ),
          child: _TaskbarWidgetPill(
            item: it,
            isSelected: isSelected,
            onTap: it.itemIndex != null && onSelectItem != null
                ? () => onSelectItem!(it.itemIndex!)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildSystemTray(TaskPinTheme theme, int pinnedCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
      decoration: BoxDecoration(
        color: theme.bg.window.withValues(alpha: 0.5),
        border: Border(
          left: BorderSide(color: theme.stroke.divider),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Pinned slot count indicator
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s8,
              vertical: TpSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: pinnedCount > slotLimit
                  ? theme.status.subtleOf(TpStateKind.critical)
                  : theme.bg.cardSecondary,
              borderRadius: TpRadius.chip,
              border: Border.all(
                color: pinnedCount > slotLimit
                    ? theme.status.critical
                    : theme.stroke.divider,
              ),
            ),
            child: Text(
              '$pinnedCount/$slotLimit Pinned',
              style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                    color: pinnedCount > slotLimit
                        ? theme.status.critical
                        : theme.text.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: TpSpacing.s12),

          // Windows Tray Chevron
          Icon(
            Icons.keyboard_arrow_up,
            size: 16,
            color: theme.text.tertiary,
          ),
          const SizedBox(width: TpSpacing.s8),

          // Network Glyph
          Icon(
            Icons.wifi,
            size: 14,
            color: theme.text.tertiary,
          ),
          const SizedBox(width: TpSpacing.s8),

          // Audio Glyph
          Icon(
            Icons.volume_up,
            size: 14,
            color: theme.text.tertiary,
          ),
          const SizedBox(width: TpSpacing.s12),

          // Digital Clock
          Text(
            mockTime,
            style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                  color: theme.text.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TaskbarWidgetPill extends StatelessWidget {
  const _TaskbarWidgetPill({
    required this.item,
    required this.isSelected,
    this.onTap,
  });

  final TpTaskbarFlightStripItem item;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Color background = item.background ??
            (isSelected
                ? theme.subtle.hover
                : (hovered ? theme.bg.flyout : theme.bg.cardSecondary));

        final Color borderColor = isSelected
            ? theme.accent.fill
            : (hovered ? theme.control.strokeStrong : theme.stroke.divider);

        return TpFocusRing(
          radius: TpRadius.control,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: theme.accent.fill.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // State Strip on the left
                if (item.state != TpBarState.running) ...<Widget>[
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: TpBarPreviewStrip.stateColor(item.state),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  const SizedBox(width: TpSpacing.s6),
                ],

                // Visual segment icon or dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? theme.accent.fill : theme.text.tertiary,
                  ),
                ),
                const SizedBox(width: TpSpacing.s6),

                // Name or rendered spans
                if (item.spans.isNotEmpty)
                  Text(
                    item.spans.map((TpBarSpan s) => s.text).join(' '),
                    style: TextStyle(
                      fontFamily: TpBarTypography.windowsFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: item.spans.first.color ?? theme.text.primary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  )
                else
                  Text(
                    item.name,
                    style: TpTypography.body.toTextStyle(tabular: true).copyWith(
                          fontSize: 12,
                          color: isSelected
                              ? theme.text.primary
                              : theme.text.secondary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),

                if (item.width != null && item.width! > 0) ...<Widget>[
                  const SizedBox(width: TpSpacing.s6),
                  Text(
                    '${item.width!.round()}px',
                    style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                          fontSize: 12,
                          color: theme.text.disabled,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
