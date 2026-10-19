// Settings (docs/VISUAL_SPEC.md section 5.7).
//
// Only settings that exist today are shown: the `global` block of config.json
// (width, pos_x, pos_y, font_size, font_color, bg_color, scroll_enabled,
// log_level), the plugin source list, the app theme mode, and the updater.
//
// Not shown, because nothing backs them: a language setting and
// "check for updates automatically". "Start with Windows" has no config field
// either.
//
// The two colours use `ConfigColorField`, which converts between the stored BGR
// COLORREF and what the user sees.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../../app/shell/app_page.dart';
import '../../app/shell/app_shell.dart' show appThemeModeProvider;
import '../../core/app/app_providers.dart';
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../core/update/update_models.dart';
import '../../core/update/update_service.dart';
import '../signals/widgets/config_color_field.dart';

/// Project page.
const String kGithubUrl = 'https://github.com/bestK/taskpin';

/// Issue tracker.
const String kFeedbackUrl = 'https://github.com/bestK/taskpin/issues';

/// Width of number and select controls.
const double kSettingsControlWidth = 160;

/// Width of colour controls.
const double kSettingsColorWidth = 260;

/// The settings page.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checking = false;

  void _edit(void Function(TaskPinConfig c) mutate) =>
      ref.read(configProvider.notifier).editGlobal(mutate);

  Future<void> _checkForUpdates() async {
    final AppLocalizations l10n = context.l10n;
    setState(() => _checking = true);
    final UpdateService service = ref.read(updateServiceProvider);
    final UpdateCheckResult result = await service.checkOnce();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateStatus.checkFailed:
        TpToastHost.show(
          context,
          TpToast(message: l10n.barUpdateFailed, kind: TpStateKind.critical),
        );
      case UpdateStatus.upToDate:
        TpToastHost.show(
          context,
          TpToast(message: l10n.barUpToDate, kind: TpStateKind.success),
        );
      case UpdateStatus.available:
        final bool? yes = await TpConfirmDialog.show(
          context,
          title: l10n.updateAvailableTitle,
          message: l10n.barUpdateAvailable.replaceFirst('%s', result.remoteVersion),
          confirmLabel: l10n.updateConfirm,
          cancelLabel: l10n.updateLater,
        );
        if (yes == true) {
          await service.apply(result);
        }
    }
  }

  Future<void> _open(String url) => const PlatformUrlOpener().open(url);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final TaskPinConfig config = ref.watch(configProvider);
    final ThemeMode mode = ref.watch(appThemeModeProvider);
    final String version = ref.watch(appVersionProvider);

    return AppPage(
      title: l10n.settingsTitle,
      children: <Widget>[
        TpSettingsSection(
          title: l10n.settingsSectionAppearance,
          children: <Widget>[
            TpSettingsCard(
              title: l10n.settingsTheme,
              description: l10n.settingsThemeDesc,
              icon: TpIcons.palette,
              trailing: SizedBox(
                width: 200,
                child: TpSelect<ThemeMode>(
                  value: mode,
                  items: <TpSelectItem<ThemeMode>>[
                    TpSelectItem<ThemeMode>(
                      value: ThemeMode.light,
                      label: l10n.settingsThemeLight,
                    ),
                    TpSelectItem<ThemeMode>(
                      value: ThemeMode.dark,
                      label: l10n.settingsThemeDark,
                    ),
                    TpSelectItem<ThemeMode>(
                      value: ThemeMode.system,
                      label: l10n.settingsThemeSystem,
                    ),
                  ],
                  onChanged: (ThemeMode? m) {
                    if (m != null) {
                      ref.read(appThemeModeProvider.notifier).state = m;
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        TpSettingsSection(
          title: l10n.settingsSectionDefaults,
          children: <Widget>[
            TpSettingsCard(
              title: l10n.settingsDefaultWidth,
              description: l10n.settingsDefaultWidthDesc,
              trailing: SizedBox(
                width: kSettingsControlWidth,
                child: TpNumberField(
                  value: config.width,
                  min: 50,
                  max: 800,
                  suffix: 'px',
                  onChanged: (num? v) =>
                      _edit((TaskPinConfig c) => c.width = v?.round() ?? 320),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsDefaultPosX,
              description: l10n.settingsDefaultPosXDesc,
              trailing: SizedBox(
                width: kSettingsControlWidth,
                child: TpNumberField(
                  value: config.posX,
                  min: -1,
                  onChanged: (num? v) =>
                      _edit((TaskPinConfig c) => c.posX = v?.round() ?? -1),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsDefaultPosY,
              description: l10n.settingsDefaultPosYDesc,
              trailing: SizedBox(
                width: kSettingsControlWidth,
                child: TpNumberField(
                  value: config.posY,
                  min: -1,
                  onChanged: (num? v) =>
                      _edit((TaskPinConfig c) => c.posY = v?.round() ?? -1),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsFontSizeTitle,
              description: l10n.settingsFontSizeDesc,
              trailing: SizedBox(
                width: kSettingsControlWidth,
                child: TpNumberField(
                  value: config.fontSize,
                  min: 6,
                  max: 32,
                  suffix: 'pt',
                  onChanged: (num? v) =>
                      _edit((TaskPinConfig c) => c.fontSize = v?.round() ?? 9),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsFontColorTitle,
              description: l10n.settingsFontColorDesc,
              trailing: SizedBox(
                width: kSettingsColorWidth,
                child: ConfigColorField(
                  wireValue: config.fontColor,
                  allowInherit: false,
                  onChanged: (String v) =>
                      _edit((TaskPinConfig c) => c.fontColor = v),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsBgColorTitle,
              description: l10n.settingsBgColorDesc,
              trailing: SizedBox(
                width: kSettingsColorWidth,
                child: ConfigColorField(
                  wireValue: config.bgColor,
                  allowInherit: false,
                  onChanged: (String v) =>
                      _edit((TaskPinConfig c) => c.bgColor = v),
                ),
              ),
            ),
            TpSettingsCard(
              title: l10n.settingsScrollTitle,
              description: l10n.settingsScrollDesc,
              trailing: TpSwitch(
                value: config.scrollEnabled,
                onChanged: (bool v) =>
                    _edit((TaskPinConfig c) => c.scrollEnabled = v),
              ),
            ),
          ],
        ),
        TpSettingsSection(
          title: l10n.settingsSectionLogging,
          children: <Widget>[
            TpSettingsCard(
              title: l10n.settingsLogLevelTitle,
              description: l10n.settingsLogLevelDesc,
              trailing: SizedBox(
                width: kSettingsControlWidth,
                child: TpSelect<int>(
                  value: config.logLevel,
                  items: <TpSelectItem<int>>[
                    TpSelectItem<int>(value: 0, label: l10n.settingsLogOff),
                    TpSelectItem<int>(value: 1, label: l10n.settingsLogError),
                    TpSelectItem<int>(value: 2, label: l10n.settingsLogInfo),
                    TpSelectItem<int>(value: 3, label: l10n.settingsLogDebug),
                  ],
                  onChanged: (int? v) =>
                      _edit((TaskPinConfig c) => c.logLevel = v ?? 0),
                ),
              ),
            ),
          ],
        ),
        TpSettingsSection(
          title: l10n.settingsSectionUpdates,
          children: <Widget>[
            TpSettingsCard(
              title: l10n.settingsVersion(version),
              icon: TpIcons.refresh,
              trailing: TpButton(
                label: _checking ? l10n.settingsChecking : l10n.barCheckUpdate,
                enabled: !_checking,
                onPressed: _checkForUpdates,
              ),
            ),
          ],
        ),
        TpSettingsSection(
          title: l10n.settingsSectionSources,
          children: <Widget>[
            TpSettingsExpander(
              title: l10n.settingsSourcesTitle(config.sources.length),
              icon: TpIcons.market,
              children: <Widget>[
                for (final String source in config.sources)
                  Text(
                    source,
                    style: theme.metricStyle.copyWith(
                      fontSize: 12,
                      color: theme.text.secondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
        TpSettingsSection(
          title: l10n.settingsSectionAbout,
          children: <Widget>[
            TpSettingsExpander(
              title: l10n.settingsAboutTitle(version),
              icon: TpIcons.info,
              children: <Widget>[
                _LinkRow(
                  label: l10n.settingsAboutGithub,
                  openLabel: l10n.actionOpen,
                  onOpen: () => _open(kGithubUrl),
                ),
                _LinkRow(
                  label: l10n.settingsAboutFeedback,
                  openLabel: l10n.actionOpen,
                  onOpen: () => _open(kFeedbackUrl),
                ),
                _ConfigPathRow(label: l10n.settingsConfigFile),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// One link in the About expander.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.openLabel,
    required this.onOpen,
  });

  final String label;
  final String openLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: theme.text.primary),
          ),
        ),
        TpButton(
          label: openLabel,
          icon: TpIcons.externalLink,
          variant: TpButtonVariant.text,
          onPressed: onOpen,
        ),
      ],
    );
  }
}

/// The config file path, selectable, in the About expander.
class _ConfigPathRow extends ConsumerWidget {
  const _ConfigPathRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    String path;
    try {
      path = ref.watch(configRepositoryProvider).paths.configFile;
    } on Object {
      path = '';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TpTypography.body
              .toTextStyle()
              .copyWith(color: theme.text.primary),
        ),
        SelectableText(
          path,
          style: theme.metricStyle.copyWith(
            fontSize: 12,
            color: theme.text.secondary,
          ),
        ),
      ],
    );
  }
}
