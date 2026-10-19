// Shared low-level pieces used by the component files.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../theme/taskpin_theme.dart';
import '../tokens/radius.dart';
import '../tokens/typography.dart';

/// Icon map.
///
/// On Windows the glyphs come from the `Segoe Fluent Icons` system font
/// (`Segoe MDL2 Assets` on Windows 10). Elsewhere, Material icons.
/// Components refer to these names, never to code points.
///
/// EVERY glyph is a `const IconData`, and the platform choice is a runtime pick
/// between two constants.
///
/// That shape is a build requirement, not a style preference. `flutter build
/// --release` runs the icon tree shaker, which refuses to run when it finds a
/// non-const `IconData(...)` invocation anywhere in the app ("Avoid
/// non-constant invocations of IconData"). A helper such as
/// `IconData(codePoint, fontFamily: ...)` therefore breaks the release build
/// while working in debug and in tests. CI builds with shaking on (the default),
/// so this is the shape that ships.
class TpIcons {
  const TpIcons._();

  static bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  // Navigation
  static IconData get signals => Icons.show_chart;
  static const IconData _marketWin = IconData(0xE719, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get market => _windows ? _marketWin : Icons.storefront_outlined;
  static const IconData _settingsWin = IconData(0xE713, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get settings => _windows ? _settingsWin : Icons.tune;
  static const IconData _diagnosticsWin = IconData(0xE9F9, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get diagnostics => _windows ? _diagnosticsWin : Icons.monitor_heart_outlined;
  static const IconData _menuWin = IconData(0xE700, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get menu => _windows ? _menuWin : Icons.menu;
  static const IconData _collapseWin = IconData(0xE76B, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get collapse => _windows ? _collapseWin : Icons.chevron_left;
  static const IconData _expandWin = IconData(0xE76C, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get expand => _windows ? _expandWin : Icons.chevron_right;
  static const IconData _backWin = IconData(0xE72B, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get back => _windows ? _backWin : Icons.arrow_back;

  // Actions
  static const IconData _addWin = IconData(0xE710, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get add => _windows ? _addWin : Icons.add;
  static IconData get remove => Icons.remove;
  static const IconData _closeWin = IconData(0xE8BB, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get close => _windows ? _closeWin : Icons.close;
  static const IconData _checkWin = IconData(0xE73E, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get check => _windows ? _checkWin : Icons.check;
  static const IconData _editWin = IconData(0xE70F, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get edit => _windows ? _editWin : Icons.edit_outlined;
  static const IconData _deleteWin = IconData(0xE74D, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get delete => _windows ? _deleteWin : Icons.delete_outline;
  static const IconData _copyWin = IconData(0xE8C8, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get copy => _windows ? _copyWin : Icons.content_copy;
  static const IconData _refreshWin = IconData(0xE72C, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get refresh => _windows ? _refreshWin : Icons.refresh;
  static const IconData _searchWin = IconData(0xE721, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get search => _windows ? _searchWin : Icons.search;
  static const IconData _downloadWin = IconData(0xE896, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get download => _windows ? _downloadWin : Icons.download_outlined;
  static const IconData _playWin = IconData(0xE768, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get play => _windows ? _playWin : Icons.play_arrow;
  static const IconData _pinWin = IconData(0xE718, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get pin => _windows ? _pinWin : Icons.push_pin_outlined;
  static const IconData _unpinWin = IconData(0xE77A, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get unpin => _windows ? _unpinWin : Icons.push_pin;

  // Disclosure
  static const IconData _chevronDownWin = IconData(0xE70D, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get chevronDown => _windows ? _chevronDownWin : Icons.keyboard_arrow_down;
  static const IconData _chevronUpWin = IconData(0xE70E, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get chevronUp => _windows ? _chevronUpWin : Icons.keyboard_arrow_up;
  static const IconData _chevronRightWin = IconData(0xE76C, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get chevronRight => _windows ? _chevronRightWin : Icons.chevron_right;
  static const IconData _moreWin = IconData(0xE712, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get more => _windows ? _moreWin : Icons.more_horiz;

  // Fields
  static const IconData _folderWin = IconData(0xE838, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get folder => _windows ? _folderWin : Icons.folder_open;
  static IconData get file => Icons.insert_drive_file_outlined;
  static IconData get palette => Icons.palette_outlined;
  static IconData get code => Icons.code;
  static IconData get dragHandle => Icons.drag_indicator;

  // Taskbar tray (decorative in the preview only)
  static const IconData _networkWin = IconData(0xE701, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get network => _windows ? _networkWin : Icons.wifi;
  static const IconData _volumeWin = IconData(0xE767, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get volume => _windows ? _volumeWin : Icons.volume_up_outlined;

  // Status
  static const IconData _successWin = IconData(0xE73E, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get success => _windows ? _successWin : Icons.check_circle;
  static const IconData _warningWin = IconData(0xE7BA, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get warning => _windows ? _warningWin : Icons.warning_amber_rounded;
  static const IconData _dangerWin = IconData(0xE783, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get danger => _windows ? _dangerWin : Icons.error_outline;
  static const IconData _infoWin = IconData(0xE946, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get info => _windows ? _infoWin : Icons.info_outline;
  static IconData get clock => Icons.schedule;
  static const IconData _externalLinkWin = IconData(0xE8A7, fontFamily: 'Segoe Fluent Icons', fontFamilyFallback: <String>['Segoe MDL2 Assets']);
  static IconData get externalLink => _windows ? _externalLinkWin : Icons.open_in_new;
}

/// Text with a type role and a colour role.
class TpText extends StatelessWidget {
  const TpText(
    this.data, {
    super.key,
    this.style,
    this.role = TpTextRole.primary,
    this.tabular,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  final String data;

  /// Type role. Defaults to `body`.
  final TpTextStyleSpec? style;

  /// Colour role.
  final TpTextRole role;

  /// Force tabular figures on or off. Null keeps the role default.
  final bool? tabular;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final TpTextStyleSpec spec = style ?? TpTypography.body;
    return Text(
      data,
      style: spec.toTextStyle(tabular: tabular).copyWith(
            color: theme.textColor(role),
          ),
      maxLines: maxLines,
      overflow: overflow ?? (maxLines == null ? null : TextOverflow.ellipsis),
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}

/// A numeric or code readout. Mono with tabular figures.
class TpMetric extends StatelessWidget {
  const TpMetric(
    this.data, {
    super.key,
    this.role = TpTextRole.primary,
    this.spec,
    this.maxLines,
  });

  final String data;
  final TpTextRole role;

  /// Overrides the type role. Defaults to `mono`.
  final TpTextStyleSpec? spec;

  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Text(
      data,
      style: (spec ?? TpTypography.mono)
          .toTextStyle(tabular: true)
          .copyWith(color: theme.textColor(role)),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// A 1 px rule in `stroke.divider`. Horizontal or vertical.
class TpDivider extends StatelessWidget {
  const TpDivider({super.key, this.vertical = false, this.thickness = 1});

  final bool vertical;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return vertical
        ? SizedBox(
            width: thickness,
            child: ColoredBox(color: theme.stroke.divider),
          )
        : SizedBox(
            height: thickness,
            child: ColoredBox(color: theme.stroke.divider),
          );
  }
}

/// A surface: card, flyout, dialog or recessed well.
///
/// Cards have a 1 px `stroke.card` outline and no shadow. Flyouts and dialogs
/// use the flyout background and their shadow.
class TpSurface extends StatelessWidget {
  const TpSurface({
    super.key,
    required this.child,
    this.level = TpSurfaceLevel.card,
    this.radius,
    this.padding,
    this.bordered = true,
    this.clip = false,
  });

  final Widget child;
  final TpSurfaceLevel level;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? padding;
  final bool bordered;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    final Color color;
    final BorderRadius r;
    final List<BoxShadow> shadow;
    final Color outline;
    switch (level) {
      case TpSurfaceLevel.window:
        color = theme.bg.window;
        r = radius ?? BorderRadius.zero;
        shadow = const <BoxShadow>[];
        outline = theme.stroke.card;
        break;
      case TpSurfaceLevel.inset:
        color = theme.bg.cardSecondary;
        r = radius ?? TpRadius.control;
        shadow = const <BoxShadow>[];
        outline = theme.stroke.divider;
        break;
      case TpSurfaceLevel.card:
        color = theme.bg.card;
        r = radius ?? TpRadius.card;
        shadow = const <BoxShadow>[];
        outline = theme.stroke.card;
        break;
      case TpSurfaceLevel.flyout:
        color = theme.bg.flyout;
        r = radius ?? TpRadius.overlay;
        shadow = theme.shadowFlyout;
        outline = theme.stroke.card;
        break;
      case TpSurfaceLevel.dialog:
        color = theme.bg.flyout;
        r = radius ?? TpRadius.overlay;
        shadow = theme.shadowDialog;
        outline = theme.stroke.card;
        break;
    }

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: r,
        border: bordered ? Border.all(color: outline) : null,
        boxShadow: shadow,
      ),
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child),
    );

    if (clip) {
      box = ClipRRect(borderRadius: r, child: box);
    }
    return box;
  }
}

/// Which surface a [TpSurface] is.
enum TpSurfaceLevel {
  /// The window ground.
  window,

  /// A recessed well: code blocks, log areas.
  inset,

  /// A settings card or list group. No shadow.
  card,

  /// A menu, dropdown or tooltip. Flyout shadow.
  flyout,

  /// A dialog. Dialog shadow.
  dialog,
}

/// Paints a [color] band of [width] along the bottom edge of [child].
///
/// Used for input and button bottom edges. A `Border` with per-side colours
/// cannot be combined with a radius, so the edge is drawn as a clipped child
/// band instead.
Widget tpWithBottomEdge(
  Widget child, {
  required Color color,
  required double width,
  required BorderRadius radius,
}) {
  return ClipRRect(
    borderRadius: radius,
    child: Stack(
      children: <Widget>[
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: width,
          child: ColoredBox(color: color),
        ),
      ],
    ),
  );
}
