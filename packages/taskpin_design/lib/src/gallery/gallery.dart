// The gallery.
//
// Renders every component in the library, in BOTH themes, so a human can
// eyeball the whole system without starting the app. This is the plan's
// "debug-only `/gallery` 路由" — the widget is here; wiring it to a route and
// gating it on `kDebugMode` is Phase 5's job.
//
// Each section shows a dark panel and a light panel side by side, because the
// whole point of the light theme being a first-class citizen is that it must
// be reviewed, not assumed.

import 'package:flutter/material.dart';

import '../components/bar.dart';
import '../components/code.dart';
import '../components/data.dart';
import '../components/feedback.dart';
import '../components/list.dart';
import '../components/settings.dart';
import '../components/forms.dart';
import '../components/shell.dart';
import '../components/status.dart';
import '../components/ui.dart';
import '../models/bar_span.dart';
import '../models/param_decl.dart';
import '../theme/taskpin_theme.dart';
import '../tokens/bar_tokens.dart';
import '../tokens/elevation.dart';
import '../tokens/primitives.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/color_hex.dart';

/// Every component, in both themes.
///
/// Stateful only to hold the interactive demo state (selected rows, toggle
/// values, text controllers) that some components need in order to render
/// meaningfully.
class TaskPinGallery extends StatefulWidget {
  const TaskPinGallery({super.key, this.initialBrightness = Brightness.dark});

  /// Which theme the page chrome uses. The component panels always show both.
  final Brightness initialBrightness;

  @override
  State<TaskPinGallery> createState() => _TaskPinGalleryState();
}

class _TaskPinGalleryState extends State<TaskPinGallery> {
  late Brightness _brightness = widget.initialBrightness;

  // Demo state, so interactive components have something real to show.
  int _selectedNav = 0;
  int _selectedGridRow = 0;
  bool _switchOn = true;
  bool _switchOff = false;
  int _segment = 1;
  bool _pinned = true;
  String _intervalUnit = 's';
  double _progress = 0.4;

  final TextEditingController _text = TextEditingController(text: '5');
  final TextEditingController _code = TextEditingController(
    text: '-- hud_clock.lua\n'
        'local t = os.date("%H:%M:%S")\n'
        'return font(t, "#E6EAF0"), false, ""',
  );
  final TextEditingController _expression =
      TextEditingController(text: r'$.subscriptionTitle');

  final List<TpHeaderEntry> _headers = <TpHeaderEntry>[
    const TpHeaderEntry(name: 'x-api-key', value: 'sk-...'),
  ];

  final List<TpParamValue> _params = <TpParamValue>[
    const TpParamValue(
      decl: TpParamDecl(
        key: 'BASE_URL',
        type: TpParamType.string,
        label: 'API address',
      ),
      value: 'https://api.example.com',
    ),
    const TpParamValue(
      decl: TpParamDecl(
        key: 'USER_ID',
        type: TpParamType.number,
        label: 'User ID',
      ),
      value: '123',
    ),
    const TpParamValue(
      decl: TpParamDecl(
        key: 'VERBOSE',
        type: TpParamType.boolean,
        label: 'Verbose logging',
      ),
      value: 'true',
    ),
  ];

  @override
  void dispose() {
    _text.dispose();
    _code.dispose();
    _expression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = _brightness == Brightness.dark
        ? TaskPinTheme.dark()
        : TaskPinTheme.light();

    return Theme(
      data: theme.toThemeData(),
      // The gallery is a self-contained review surface: it must render inside a
      // bare `MaterialApp(home: TaskPinGallery())`, not only under the app's
      // `Scaffold`. Several components wrap real Material widgets (TextField,
      // DropdownButton, Slider), which require a Material ancestor — so the
      // gallery supplies one itself rather than making the caller remember to.
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: theme.bg.window,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TpSpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _pageHeader(theme),
                const SizedBox(height: TpSpacing.s32),

                _section('Colour tokens', _colourTokens(theme)),
                _section('Typography', _typography(theme)),
                _section('Spacing · Radius · Elevation', _scales(theme)),
                _section('Status', _statusSection(theme)),
                _section('Buttons', _buttons(theme)),
                _section('Shell', _shellSection(theme)),
                _section('Data', _dataSection(theme)),
                _section('Forms', _formsSection(theme)),
                _section('Feedback', _feedbackSection(theme)),
                _section('Settings', _settingsSection(theme)),
                _section('Lists', _listSection(theme)),
                _section('Code', _codeSection(theme)),
                _section('Bar', _barSection(theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Chrome ---------------------------------------------------------------

  Widget _pageHeader(TaskPinTheme theme) {
    return TpPageHeader(
      title: 'TaskPin design system',
      description:
          'Every component, in both themes. Dark-first, one accent, tabular '
          'numerals on every metric.',
      actions: <Widget>[
        TpSegmentedControl<Brightness>(
          value: _brightness,
          segments: const <TpSelectItem<Brightness>>[
            TpSelectItem<Brightness>(
              value: Brightness.dark,
              label: 'Dark',
            ),
            TpSelectItem<Brightness>(
              value: Brightness.light,
              label: 'Light',
            ),
          ],
          onChanged: (Brightness b) => setState(() => _brightness = b),
        ),
      ],
    );
  }

  Widget _section(String title, Widget body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TpSpacing.s40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TpText(title),
          const SizedBox(height: TpSpacing.s12),
          body,
        ],
      ),
    );
  }

  /// Render [builder] in both themes, side by side.
  ///
  /// This is the gallery's whole reason for existing: the same widget, two
  /// themes, one screen.
  Widget _both(Widget Function(BuildContext context, TaskPinTheme theme) builder) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth > 900;
        final Widget dark = _panel(TaskPinTheme.dark(), builder, 'Dark');
        final Widget light = _panel(TaskPinTheme.light(), builder, 'Light');
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              dark,
              const SizedBox(height: TpSpacing.s16),
              light,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: dark),
            const SizedBox(width: TpSpacing.s16),
            Expanded(child: light),
          ],
        );
      },
    );
  }

  Widget _panel(
    TaskPinTheme theme,
    Widget Function(BuildContext context, TaskPinTheme theme) builder,
    String label,
  ) {
    return Theme(
      data: theme.toThemeData(),
      child: Builder(
        builder: (BuildContext context) => Container(
          padding: const EdgeInsets.all(TpSpacing.s16),
          decoration: BoxDecoration(
            color: theme.bg.window,
            borderRadius: TpRadius.card,
            border: Border.all(color: theme.stroke.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  TpText(label),
                  const Spacer(),
                  Text(
                    theme.isDark ? 'Brightness.dark' : 'Brightness.light',
                    style: TpTypography.caption.toTextStyle().copyWith(
                          color: theme.text.disabled,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: TpSpacing.s12),
              builder(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  // -- Sections -------------------------------------------------------------

  Widget _colourTokens(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      final Map<String, Color> groups = <String, Color>{
        'bg/window': t.bg.window,
        'bg/card': t.bg.card,
        'bg/cardSecondary': t.bg.cardSecondary,
        'bg/flyout': t.bg.flyout,
        'stroke/card': t.stroke.card,
        'stroke/divider': t.stroke.divider,
        'control/fill': t.control.fill,
        'control/fillHover': t.control.fillHover,
        'control/fillPressed': t.control.fillPressed,
        'control/fillInputActive': t.control.fillInputActive,
        'control/stroke': t.control.stroke,
        'control/strokeBottom': t.control.strokeBottom,
        'control/strokeStrong': t.control.strokeStrong,
        'subtle/hover': t.subtle.hover,
        'subtle/pressed': t.subtle.pressed,
        'text/primary': t.text.primary,
        'text/secondary': t.text.secondary,
        'text/tertiary': t.text.tertiary,
        'text/disabled': t.text.disabled,
        'accent/fill': t.accent.fill,
        'accent/fillHover': t.accent.fillHover,
        'accent/onFill': t.accent.onFill,
        'accent/text': t.accent.text,
        'status/success': t.status.success,
        'status/caution': t.status.caution,
        'status/critical': t.status.critical,
        'status/neutral': t.status.neutral,
        'smoke': t.smoke,
        'focus/outer': t.focusOuter,
        'focus/inner': t.focusInner,
      };

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: TpSpacing.s8,
            runSpacing: TpSpacing.s8,
            children: <Widget>[
              for (final MapEntry<String, Color> e in groups.entries)
                _swatch(t, e.key, e.value),
            ],
          ),
        ],
      );
    });
  }

  Widget _swatch(TaskPinTheme t, String name, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 72,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: TpRadius.control,
            border: Border.all(color: t.stroke.divider),
          ),
        ),
        const SizedBox(height: TpSpacing.s4),
        SizedBox(
          width: 72,
          child: Text(
            name,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: t.text.tertiary,
                ),
            maxLines: 2,
          ),
        ),
        Text(
          TpColorHex.toWire(color),
          style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                color: t.text.disabled,
              ),
        ),
      ],
    );
  }

  Widget _ramp(TaskPinTheme t, String name, List<Color> steps) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            name,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: t.text.tertiary,
                ),
          ),
        ),
        Expanded(
          child: Row(
            children: <Widget>[
              for (final Color c in steps)
                Expanded(
                  child: Container(
                    height: 24,
                    color: c,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typography(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final MapEntry<String, TpTextStyleSpec> e
              in TpTypography.all.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: TpSpacing.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  SizedBox(
                    width: 84,
                    child: Text(
                      e.key,
                      style: TpTypography.caption.toTextStyle().copyWith(
                            color: t.text.tertiary,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.key == 'mono'
                          ? 'return font("CPU 42%", "#3FB950")'
                          : 'The quick brown fox 0123456789',
                      style: e.value.toTextStyle().copyWith(
                            color: t.text.primary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: TpSpacing.s8),
          TpText('Tabular figures (metrics)'),
          const SizedBox(height: TpSpacing.s6),
          Row(
            children: <Widget>[
              TpMetric('CPU 9%'),
              const SizedBox(width: TpSpacing.s24),
              TpMetric('CPU 100%'),
              const SizedBox(width: TpSpacing.s24),
              TpMetric('1,234.56 MB'),
            ],
          ),
        ],
      );
    });
  }

  Widget _scales(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpText('Spacing'),
          const SizedBox(height: TpSpacing.s8),
          Row(
            children: <Widget>[
              for (final double s in TpSpacing.steps)
                Padding(
                  padding: const EdgeInsets.only(right: TpSpacing.s4),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: s,
                        height: 24,
                        color: t.accent.fill,
                      ),
                      const SizedBox(height: TpSpacing.s4),
                      Text(
                        s.toStringAsFixed(0),
                        style: TpTypography.caption
                            .toTextStyle(tabular: true)
                            .copyWith(color: t.text.tertiary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Radius'),
          const SizedBox(height: TpSpacing.s8),
          Row(
            children: <Widget>[
              for (final double r in <double>[
                TpRadius.controlValue,
                TpRadius.controlValue,
                TpRadius.cardValue,
                TpRadius.cardValue,
                TpRadius.overlayValue,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: TpSpacing.s8),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: t.bg.card,
                          border: Border.all(color: t.control.strokeStrong),
                          borderRadius: BorderRadius.circular(r),
                        ),
                      ),
                      const SizedBox(height: TpSpacing.s4),
                      Text(
                        r.toStringAsFixed(0),
                        style: TpTypography.caption
                            .toTextStyle(tabular: true)
                            .copyWith(color: t.text.tertiary),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: TpSpacing.s8),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: t.bg.card,
                        border: Border.all(color: t.control.strokeStrong),
                        borderRadius: TpRadius.chip,
                      ),
                    ),
                    const SizedBox(height: TpSpacing.s4),
                    Text(
                      'pill',
                      style: TpTypography.caption
                          .toTextStyle()
                          .copyWith(color: t.text.tertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Elevation 0-3'),
          const SizedBox(height: TpSpacing.s8),
          Row(
            children: <Widget>[
              for (final MapEntry<String, List<BoxShadow>> e in <String, List<BoxShadow>>{'flyout': t.shadowFlyout, 'dialog': t.shadowDialog}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: TpSpacing.s16),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 40,
                        decoration: BoxDecoration(
                          color: t.bg.card,
                          borderRadius: TpRadius.control,
                          boxShadow: e.value,
                        ),
                      ),
                      const SizedBox(height: TpSpacing.s6),
                      Text(
                        e.key,
                        style: TpTypography.caption
                            .toTextStyle()
                            .copyWith(color: t.text.tertiary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }

  Widget _statusSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: TpSpacing.s16,
            runSpacing: TpSpacing.s12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: const <Widget>[
              TpStatusDot(kind: TpStateKind.success),
              TpStatusDot(kind: TpStateKind.caution),
              TpStatusDot(kind: TpStateKind.critical),
              TpStatusDot(kind: TpStateKind.info),
              TpStatusDot(kind: TpStateKind.neutral),
              TpStatusPill(label: 'RUNNING', kind: TpStateKind.success),
              TpStatusPill(label: 'STALE', kind: TpStateKind.caution),
              TpStatusPill(label: 'ERROR', kind: TpStateKind.critical),
              TpStatusPill(label: 'PAUSED', kind: TpStateKind.neutral),
              TpIntervalBadge(interval: Duration(milliseconds: 500)),
              TpIntervalBadge(interval: Duration(seconds: 5)),
              TpIntervalBadge(interval: Duration(seconds: 30)),
              TpIntervalBadge(interval: Duration(minutes: 5)),
              TpIntervalBadge(interval: Duration(minutes: 90)),
              TpIntervalBadge(
                interval: Duration(milliseconds: 250),
                warning: true,
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('RelativeTime'),
          const SizedBox(height: TpSpacing.s8),
          Wrap(
            spacing: TpSpacing.s24,
            runSpacing: TpSpacing.s8,
            children: <Widget>[
              TpRelativeTime(
                timestamp: DateTime(2026, 1, 1, 12, 0, 0),
                now: DateTime(2026, 1, 1, 12, 0, 0),
              ),
              TpRelativeTime(
                timestamp: DateTime(2026, 1, 1, 12, 0, 0),
                now: DateTime(2026, 1, 1, 12, 0, 42),
              ),
              TpRelativeTime(
                timestamp: DateTime(2026, 1, 1, 12, 0, 0),
                now: DateTime(2026, 1, 1, 12, 5, 0),
              ),
              TpRelativeTime(
                timestamp: DateTime(2026, 1, 1, 12, 0, 0),
                now: DateTime(2026, 1, 1, 12, 0, 30),
                staleAfter: const Duration(seconds: 10),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Sparkline'),
          const SizedBox(height: TpSpacing.s8),
          Row(
            children: <Widget>[
              TpSparkline(
                values: const <double?>[
                  12,
                  18,
                  15,
                  22,
                  30,
                  28,
                  41,
                  38,
                  45,
                  52,
                ],
                width: 120,
                height: 32,
              ),
              const SizedBox(width: TpSpacing.s16),
              const TpSparkline(
                values: <double?>[5, 5, 5, 5, 5, 5],
                width: 120,
                height: 32,
              ),
              const SizedBox(width: TpSpacing.s16),
              const TpSparkline(
                values: <double?>[],
                width: 120,
                height: 32,
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _buttons(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: TpSpacing.s12,
            runSpacing: TpSpacing.s12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TpButton(
                label: 'Primary',
                variant: TpButtonVariant.primary,
                onPressed: () {},
              ),
              TpButton(label: 'Secondary', onPressed: () {}),
              TpButton(
                label: 'Ghost',
                variant: TpButtonVariant.text,
                onPressed: () {},
              ),
              TpButton(
                label: 'Delete',
                variant: TpButtonVariant.standard,
                onPressed: () {},
              ),
              TpButton(
                label: 'With icon',
                icon: TpIcons.refresh,
                onPressed: () {},
              ),
              const TpButton(label: 'Disabled', onPressed: null),
              const TpButton(
                label: 'Disabled primary',
                variant: TpButtonVariant.primary,
                onPressed: null,
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Tooltip (hover or focus)'),
          const SizedBox(height: TpSpacing.s8),
          TpTooltip(
            message: 'Re-run this script now',
            shortcut: 'Ctrl+R',
            child: TpButton(label: 'Hover me', onPressed: () {}),
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Segmented control'),
          const SizedBox(height: TpSpacing.s8),
          TpSegmentedControl<int>(
            value: _segment,
            segments: const <TpSelectItem<int>>[
              TpSelectItem<int>(value: 0, label: 'Cards'),
              TpSelectItem<int>(value: 1, label: 'Table'),
              TpSelectItem<int>(value: 2, label: 'JSON'),
            ],
            onChanged: (int v) => setState(() => _segment = v),
          ),
        ],
      );
    });
  }

  Widget _shellSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpText('NavRail'),
          const SizedBox(height: TpSpacing.s8),
          SizedBox(
            height: 200,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TpNavRail(
                    destinations: <TpNavDestination>[
                      TpNavDestination(
                        label: 'Signals',
                        icon: TpIcons.signals,
                        route: '/signals',
                      ),
                      TpNavDestination(
                        label: 'Market',
                        icon: TpIcons.market,
                        route: '/market',
                        badgeCount: 3,
                      ),
                      TpNavDestination(
                        label: 'Settings',
                        icon: TpIcons.settings,
                        route: '/settings',
                      ),
                    ],
                    selectedRoute: '/signals',
                    onSelect: (_) {},
                  ),
                ),
                const SizedBox(width: TpSpacing.s16),
                Expanded(
                  child: TpNavRail(
                    destinations: <TpNavDestination>[
                      TpNavDestination(
                        label: 'Signals',
                        icon: TpIcons.signals,
                        route: '/signals',
                      ),
                      TpNavDestination(
                        label: 'Market',
                        icon: TpIcons.market,
                        route: '/market',
                        badgeCount: 3,
                      ),
                    ],
                    selectedRoute: '/market',
                    collapsed: true,
                    onSelect: (_) {},
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Toolbar'),
          const SizedBox(height: TpSpacing.s8),
          TpToolbar(
            leading: <Widget>[
              TpButton(label: 'Add signal', icon: TpIcons.add, onPressed: () {}),
            ],
            trailing: <Widget>[
              TpButton(label: 'Refresh', icon: TpIcons.refresh, onPressed: () {}),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('SplitPane (drag, or arrow keys when focused)'),
          const SizedBox(height: TpSpacing.s8),
          SizedBox(
            height: 120,
            child: TpSplitPane(
              master: Container(
                color: t.bg.card,
                alignment: Alignment.center,
                child: TpMetric('master'),
              ),
              detail: Container(
                color: t.bg.cardSecondary,
                alignment: Alignment.center,
                child: TpMetric('detail'),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _dataSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpText('SignalCard'),
          const SizedBox(height: TpSpacing.s8),
          TpSignalCard(
            name: 'CPU',
            kind: TpStateKind.success,
            value: '42',
            unit: '%',
            interval: const Duration(seconds: 2),
            lastUpdated: DateTime(2026, 1, 1, 12, 0, 0),
            source: 'system_monitor.lua',
            sparklineValues: const <double?>[
              12,
              18,
              15,
              22,
              30,
              28,
              41,
              42,
            ],
            pinned: _pinned,
            onPin: () => setState(() => _pinned = !_pinned),
            onTap: () {},
          ),
          const SizedBox(height: TpSpacing.s12),
          TpSignalCard(
            name: 'NewAPI balance',
            kind: TpStateKind.critical,
            value: '—',
            error: 'Lua error: attempt to index a nil value (field \'data\')',
            interval: const Duration(seconds: 30),
            lastUpdated: DateTime(2026, 1, 1, 11, 58, 0),
            source: 'newapi_balance.lua',
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('SignalGrid'),
          const SizedBox(height: TpSpacing.s8),
          TpSignalGrid(
            selectedIndex: _selectedGridRow,
            onSelect: (int i) => setState(() => _selectedGridRow = i),
            rows: <TpSignalRow>[
              TpSignalRow(
                name: 'CPU',
                kind: TpStateKind.success,
                value: '42',
                unit: '%',
                interval: const Duration(seconds: 2),
                lastUpdated: DateTime(2026, 1, 1, 12, 0, 0),
              ),
              TpSignalRow(
                name: 'Memory',
                kind: TpStateKind.success,
                value: '12.4',
                unit: 'GB',
                interval: const Duration(seconds: 2),
                lastUpdated: DateTime(2026, 1, 1, 12, 0, 0),
              ),
              TpSignalRow(
                name: 'Balance',
                kind: TpStateKind.critical,
                value: '—',
                interval: const Duration(seconds: 30),
                lastUpdated: DateTime(2026, 1, 1, 11, 58, 0),
                error: 'fetch failed',
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('MarketCard'),
          const SizedBox(height: TpSpacing.s8),
          TpMarketCard(
            name: 'github_trending',
            description:
                'Shows the top trending repository for a language, updated '
                'every 5 minutes.',
            author: 'bestK',
            sourceRepo: 'bestK/taskpin-plugins',
            installed: true,
            onInstall: () {},
            onOpen: () {},
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('KeyValueList'),
          const SizedBox(height: TpSpacing.s8),
          TpKeyValueList(
            monoValues: true,
            entries: const <String, String>{
              'id': 'zeeho',
              'type': 'lua',
              'interval_ms': '30000',
              'bar_width': '155',
            },
          ),
        ],
      );
    });
  }

  Widget _formsSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpTextField(
            controller: _text,
            label: 'Bar width',
            helper: 'Clamped 50-800 px by the native renderer.',
            trailing: Icon(TpIcons.more),
          ),
          const SizedBox(height: TpSpacing.s12),
          const TpTextField(
            label: 'With error',
            error: 'This field is required',
          ),
          const SizedBox(height: TpSpacing.s12),
          TpTextArea(
            label: 'req_headers',
            helper: 'One per line, or use the list editor below.',
            rows: 3,
          ),
          const SizedBox(height: TpSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TpNumberField(
                  value: 200,
                  label: 'Number',
                  min: 50,
                  max: 800,
                  suffix: 'px',
                ),
              ),
              const SizedBox(width: TpSpacing.s12),
              Expanded(
                child: TpIntervalField(
                  value: const Duration(seconds: 30),
                  label: 'Interval',
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TpSelect<String>(
                  value: _intervalUnit,
                  label: 'Select',
                  items: const <TpSelectItem<String>>[
                    TpSelectItem<String>(value: 'ms', label: 'Milliseconds'),
                    TpSelectItem<String>(value: 's', label: 'Seconds'),
                    TpSelectItem<String>(value: 'm', label: 'Minutes'),
                  ],
                  onChanged: (String? v) {
                    if (v != null) {
                      setState(() => _intervalUnit = v);
                    }
                  },
                ),
              ),
              const SizedBox(width: TpSpacing.s12),
              Expanded(
                child: TpColorField(
                  wireValue: 'FF4C7FE0',
                  label: 'Colour',
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          Wrap(
            spacing: TpSpacing.s24,
            runSpacing: TpSpacing.s12,
            children: <Widget>[
              TpSwitch(
                value: _switchOn,
                label: 'Enabled',
                description: 'Runs on every refresh',
                onChanged: (bool v) => setState(() => _switchOn = v),
              ),
              TpSwitch(
                value: _switchOff,
                label: 'Off',
                onChanged: (bool v) => setState(() => _switchOff = v),
              ),
              const TpSwitch(
                value: true,
                label: 'Disabled',
                onChanged: null,
              ),
            ],
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('PathPicker'),
          const SizedBox(height: TpSpacing.s8),
          TpPathPicker(
            value: r'D:\workspace\taskpin\scripts\zeeho.lua',
            label: 'Script',
            onChanged: (_) {},
            onBrowse: () async => null,
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('ParamField (from @param)'),
          const SizedBox(height: TpSpacing.s8),
          for (final TpParamValue p in _params) ...<Widget>[
            TpParamField(param: p, onChanged: (_) {}),
            const SizedBox(height: TpSpacing.s12),
          ],
          TpText('HeaderListEditor (req_headers)'),
          const SizedBox(height: TpSpacing.s8),
          TpHeaderListEditor(
            entries: _headers,
            onChanged: (List<TpHeaderEntry> next) =>
                setState(() => _headers..clear()..addAll(next)),
          ),
        ],
      );
    });
  }

  Widget _feedbackSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpText('InlineBanner'),
          const SizedBox(height: TpSpacing.s8),
          const TpInfoBar(
            kind: TpStateKind.info,
            title: 'Heads up',
            message: 'Inter is not bundled yet; text falls back to the system '
                'font until the TTFs are vendored.',
          ),
          const SizedBox(height: TpSpacing.s8),
          TpInfoBar(
            kind: TpStateKind.critical,
            title: 'Script failed',
            message: 'attempt to index a nil value (field \'data\')',
            actions: <Widget>[
              TpButton(
                label: 'Retry',
                size: TpControlSize.control,
                onPressed: () {},
              ),
              TpButton(
                label: 'Open script',
                variant: TpButtonVariant.text,
                size: TpControlSize.control,
                onPressed: () {},
              ),
            ],
            onDismiss: () {},
          ),
          const SizedBox(height: TpSpacing.s8),
          const TpInfoBar(
            kind: TpStateKind.success,
            message: 'Installed github_trending.',
          ),
          const SizedBox(height: TpSpacing.s8),
          const TpInfoBar(
            kind: TpStateKind.caution,
            message: 'This signal has not updated in 2 minutes.',
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Toast'),
          const SizedBox(height: TpSpacing.s8),
          const TpToastCard(
            toast: TpToast(
              message: 'Copied span JSON to the clipboard.',
              kind: TpStateKind.success,
            ),
          ),
          const SizedBox(height: TpSpacing.s8),
          TpToastCard(
            toast: TpToast(
              message: 'Failed to reach api.ip.sb; falling back to direct '
                  'GitHub URLs.',
              kind: TpStateKind.caution,
              actionLabel: 'Details',
              onAction: () {},
            ),
            onDismiss: () {},
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('ProgressBar'),
          const SizedBox(height: TpSpacing.s8),
          TpProgressBar(value: _progress),
          const SizedBox(height: TpSpacing.s8),
          const TpProgressBar(value: null, indeterminate: true),
          Slider(
            value: _progress,
            onChanged: (double v) => setState(() => _progress = v),
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Skeleton'),
          const SizedBox(height: TpSpacing.s8),
          const TpSkeleton(height: 16),
          const SizedBox(height: TpSpacing.s8),
          const TpSkeletonLines(count: 3),
          const SizedBox(height: TpSpacing.s16),
          TpText('EmptyState'),
          const SizedBox(height: TpSpacing.s8),
          // No fixed height: the component centres itself in whatever slot it
          // is given, so the demo lets it size to its content instead of
          // clipping it into an arbitrary box (text wrapping makes any fixed
          // height a guess).
          TpEmptyState(
            title: 'No signals yet',
            message: 'Add a signal to start monitoring.',
            action: TpButton(
              label: 'Add signal',
              icon: TpIcons.add,
              variant: TpButtonVariant.primary,
              onPressed: () {},
            ),
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('ErrorState'),
          const SizedBox(height: TpSpacing.s8),
          TpErrorState(
            title: 'Could not reach the market',
            message: 'The request to api.ip.sb timed out.',
            detail: 'SocketException: Connection timed out\n'
                '  at market.fetch (manifest.dart:42)',
            onRetry: () {},
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('ConfirmDialog (click to open)'),
          const SizedBox(height: TpSpacing.s8),
          TpButton(
            label: 'Delete signal',
            variant: TpButtonVariant.standard,
            onPressed: () => TpConfirmDialog.show(
              context,
              title: 'Delete signal?',
              message: 'This removes the item from config.json. The script '
                  'file on disk is not touched.',
              detail: 'zeeho  (scripts/zeeho.lua)',
              confirmLabel: 'Delete',
              destructive: true,
            ),
          ),
        ],
      );
    });
  }

  Widget _settingsSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpSettingsSection(
            title: 'Appearance',
            children: <Widget>[
              TpSettingsCard(
                title: 'Bar background follows the taskbar',
                description: 'Off keeps the bar transparent.',
                icon: TpIcons.palette,
                trailing: TpSwitch(
                  value: _switchOn,
                  onChanged: (bool v) => setState(() => _switchOn = v),
                ),
              ),
              TpSettingsCard(
                title: 'Market',
                description: 'Open the plugin market.',
                icon: TpIcons.market,
                onTap: () {},
              ),
              TpSettingsCard(
                title: 'Default width',
                trailing: TpButton(label: 'Reset', onPressed: () {}),
              ),
            ],
          ),
          TpSettingsSection(
            title: 'Sources',
            children: <Widget>[
              TpSettingsExpander(
                title: 'Plugin sources',
                description: 'Two sources configured.',
                icon: TpIcons.folder,
                initiallyExpanded: true,
                children: <Widget>[
                  Text(
                    'https://github.com/example/taskpin-plugins',
                    style: TpTypography.mono.toTextStyle().copyWith(
                          color: t.text.secondary,
                        ),
                  ),
                  Text(
                    'C:\\Users\\example\\plugins',
                    style: TpTypography.mono.toTextStyle().copyWith(
                          color: t.text.secondary,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _listSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return TpListGroup(
        children: <Widget>[
          TpListRow(
            title: 'Rich',
            subtitle: 'rich_text_demo.lua · every 5 s',
            leading: Icon(TpIcons.dragHandle, size: 16, color: t.text.tertiary),
            trailing: TpSwitch(value: _pinned, onChanged: (bool v) => setState(() => _pinned = v)),
            onTap: () {},
          ),
          TpListRow(
            title: 'Clock',
            trailing: TpStatusDot(kind: TpStateKind.success),
            onTap: () {},
          ),
          TpListRow(title: 'Static row'),
        ],
      );
    });
  }

  Widget _codeSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpLuaEditor(
            controller: _code,
            label: 'Script',
            minLines: 5,
          ),
          const SizedBox(height: TpSpacing.s16),
          TpExpressionEditor(
            value: _expression.text,
            label: 'Field expression',
            availablePaths: const <String>[
              r'$.subscriptionTitle',
              r'$.currentUsage',
              r'$.data.balance',
            ],
            onChanged: (String v) => _expression.text = v,
          ),
          const SizedBox(height: TpSpacing.s16),
          const TpResponsePreview(
            statusCode: 200,
            contentType: 'application/json; charset=utf-8',
            maxHeight: 140,
            body: '{\n'
                '  "subscriptionTitle": "Pro",\n'
                '  "currentUsage": "\$3.42",\n'
                '  "data": { "balance": 41.58 }\n'
                '}',
          ),
          const SizedBox(height: TpSpacing.s8),
          const TpResponsePreview(
            statusCode: 500,
            contentType: 'text/html',
            truncated: true,
            maxHeight: 90,
            body: '<html><head><title>500 Internal Server Error</title>...',
          ),
        ],
      );
    });
  }

  Widget _barSection(TaskPinTheme theme) {
    return _both((BuildContext context, TaskPinTheme t) {
      final TpBarContent content = TpBarContent(
        spans: <TpBarSpan>[
          const TpBarSpan(text: 'CPU'),
          TpBarSpan(text: '42%', color: TpBarSpan.parseWireColor('#3FB950')),
          const TpBarSpan(text: 'MEM'),
          const TpBarSpan(text: '12.4GB'),
          const TpBarSpan(text: 'NET'),
          TpBarSpan(text: '↓1.2', color: TpBarSpan.parseWireColor('#58A6FF')),
          TpBarSpan(text: '↑0.3', color: TpBarSpan.parseWireColor('#D29922')),
        ],
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpText('BarPreviewStrip — Windows (48 px, 2 lines, square)'),
          const SizedBox(height: TpSpacing.s8),
          TpBarPreviewStrip(content: content),
          const SizedBox(height: TpSpacing.s4),
          TpBarPreviewStrip(
            content: content,
            state: TpBarState.error,
            hovered: true,
          ),
          const SizedBox(height: TpSpacing.s4),
          TpBarPreviewStrip(content: content, state: TpBarState.stale),
          const SizedBox(height: TpSpacing.s4),
          TpBarPreviewStrip(content: content, state: TpBarState.loading),
          const SizedBox(height: TpSpacing.s16),
          TpText('TaskbarFlightStrip — Live Simulated OS Taskbar Dock'),
          const SizedBox(height: TpSpacing.s8),
          TpTaskbarFlightStrip(
            items: <TpTaskbarFlightStripItem>[
              TpTaskbarFlightStripItem(
                name: 'System Monitor',
                spans: content.spans,
                pinned: true,
                itemIndex: 0,
              ),
              TpTaskbarFlightStripItem(
                name: 'Claude Code',
                spans: <TpBarSpan>[
                  const TpBarSpan(text: 'Claude:'),
                  TpBarSpan(
                    text: 'Thinking (3s)',
                    color: TpBarSpan.parseWireColor('#FFA502'),
                  ),
                ],
                pinned: true,
                itemIndex: 1,
              ),
              const TpTaskbarFlightStripItem(
                name: 'NewAPI Balance',
                spans: <TpBarSpan>[
                  TpBarSpan(text: r'$41.58'),
                ],
                pinned: true,
                itemIndex: 2,
              ),
            ],
            selectedIndex: 0,
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('BarPreviewStrip — macOS (24 px, 1 line, radius 6)'),
          const SizedBox(height: TpSpacing.s8),
          TpBarPreviewStrip(
            content: content,
            platform: TpBarPlatform.macOS,
          ),
          const SizedBox(height: TpSpacing.s4),
          TpBarPreviewStrip(
            content: TpBarContent(
              spans: <TpBarSpan>[
                const TpBarSpan(text: 'CPU'),
                TpBarSpan(
                  text: '42%',
                  color: TpBarSpan.parseWireColor('#3FB950'),
                ),
                const TpBarSpan(text: 'MEM', newline: true),
                const TpBarSpan(text: '12.4GB'),
              ],
            ),
            platform: TpBarPlatform.macOS,
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('Frozen bar tokens'),
          const SizedBox(height: TpSpacing.s8),
          TpKeyValueList(
            monoValues: true,
            entries: <String, String>{
              for (final MapEntry<String, Color> e in TpBarColors.all.entries)
                e.key: TpColorHex.toWire(e.value),
            },
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('SpanInspector'),
          const SizedBox(height: TpSpacing.s8),
          TpSpanInspector(
            spans: content.spans,
            onChanged: (_) {},
          ),
          const SizedBox(height: TpSpacing.s16),
          TpText('DialogSpecPreview'),
          const SizedBox(height: TpSpacing.s8),
          TpDialogSpecPreview(
            title: 'NewAPI balance',
            items: <TpDialogSpecItem>[
              const TpDialogSpecItem(
                type: TpDialogItemType.text,
                text: 'Subscription: Pro',
              ),
              const TpDialogSpecItem(type: TpDialogItemType.hr),
              const TpDialogSpecItem(
                type: TpDialogItemType.table,
                rows: <List<String>>[
                  <String>['Model', 'Usage', 'Cost'],
                  <String>['gpt-4o', '120k', r'$3.42'],
                  <String>['claude-3', '48k', r'$1.10'],
                ],
              ),
              const TpDialogSpecItem(
                type: TpDialogItemType.image,
                text: 'chart.png',
              ),
              const TpDialogSpecItem(
                type: TpDialogItemType.button,
                text: 'Open dashboard',
              ),
            ],
          ),
        ],
      );
    });
  }
}
