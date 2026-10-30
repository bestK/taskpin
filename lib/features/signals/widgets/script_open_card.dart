// "Open the script" — the detail page's card and the list row's menu entry.
//
// Two actions, because they answer different questions: the default app is one
// click and no setup; the editor list is for someone who is going to change the
// script and wants their own tool. See `core/script/script_editor.dart` for how
// the list is found.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';
import '../../../core/script/script_editor.dart';

/// The detail page's card: the script path, then Open and Open with.
class ScriptOpenCard extends ConsumerWidget {
  const ScriptOpenCard({super.key, required this.path});

  /// Absolute path to the script. Empty disables both actions.
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<ScriptEditor> editors =
        ref.watch(scriptEditorsProvider).valueOrNull ?? const <ScriptEditor>[];
    final bool hasPath = path.isNotEmpty;

    return TpSettingsCard(
      title: l10n.detailScriptOpen,
      description: hasPath ? path : l10n.detailScriptFileDesc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpButton(
            label: l10n.actionOpen,
            icon: TpIcons.externalLink,
            enabled: hasPath,
            onPressed: () => openScriptWithDefaultApp(context, path),
          ),
          const SizedBox(width: TpSpacing.s8),
          Builder(
            builder: (BuildContext ctx) => TpButton(
              label: l10n.detailOpenWith,
              icon: TpIcons.chevronDown,
              enabled: hasPath,
              onPressed: () {
                final RenderBox box = ctx.findRenderObject()! as RenderBox;
                pickScriptEditor(
                  context,
                  path,
                  box.localToGlobal(Offset(0, box.size.height)),
                  editors,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Open [path] with the OS association, and say so when it fails.
Future<void> openScriptWithDefaultApp(
  BuildContext context,
  String path,
) async {
  if (path.isEmpty) return;
  final bool ok = await openPathWithDefaultApp(path);
  if (!ok && context.mounted) {
    TpToastHost.show(
      context,
      TpToast(
        message: context.l10n.detailOpenFailed,
        kind: TpStateKind.critical,
      ),
    );
  }
}

/// Show the detected editors at [position] and open [path] in the chosen one.
///
/// A menu rather than a submenu of the row menu: the list is discovered at
/// runtime, can be empty, and is worth showing with the executable's name.
Future<void> pickScriptEditor(
  BuildContext context,
  String path,
  Offset position,
  List<ScriptEditor> editors,
) async {
  if (path.isEmpty) return;
  final AppLocalizations l10n = context.l10n;
  final TaskPinTheme theme = TaskPinTheme.of(context);
  final Size screen = MediaQuery.sizeOf(context);

  if (editors.isEmpty) {
    TpToastHost.show(
      context,
      TpToast(message: l10n.detailOpenNoEditor, kind: TpStateKind.caution),
    );
    return;
  }

  final ScriptEditor? picked = await showMenu<ScriptEditor>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      screen.width - position.dx,
      screen.height - position.dy,
    ),
    color: theme.bg.flyout,
    surfaceTintColor: Colors.transparent,
    shadowColor: theme.shadowFlyout.first.color,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: TpRadius.card,
      side: BorderSide(color: theme.stroke.card),
    ),
    items: <PopupMenuEntry<ScriptEditor>>[
      for (final ScriptEditor editor in editors)
        PopupMenuItem<ScriptEditor>(
          value: editor,
          height: 36,
          child: Row(
            children: <Widget>[
              Icon(TpIcons.code, size: 16, color: theme.text.secondary),
              const SizedBox(width: TpSpacing.s12),
              Text(
                editor.label,
                style: TpTypography.body
                    .toTextStyle()
                    .copyWith(color: theme.text.primary),
              ),
            ],
          ),
        ),
    ],
  );
  if (picked == null || !context.mounted) return;
  final bool ok = await openPathWithEditor(picked, path);
  if (!ok && context.mounted) {
    TpToastHost.show(
      context,
      TpToast(message: l10n.detailOpenFailed, kind: TpStateKind.critical),
    );
  }
}
