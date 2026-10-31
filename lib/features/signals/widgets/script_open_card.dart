// "Open the script" — the detail page's card and the list row's menu entry.
//
// One "Open with" menu: the default app first, then the detected editors. A
// separate "Open" button beside it did the menu's first entry again. See
// `core/script/script_editor.dart` for how the editor list is found.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';
import '../../../core/script/script_editor.dart';

/// The detail page's card: the script path, then the Open with menu.
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
      trailing: Builder(
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

/// Show "Default app" and the detected editors at [position], then open [path]
/// with the choice.
///
/// A menu rather than a submenu of the row menu: the list is discovered at
/// runtime, can be empty, and is worth showing with the executable's name.
/// With no editors found the menu still offers the default app.
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

  PopupMenuItem<_OpenChoice> entry(
          _OpenChoice value, IconData icon, String label) =>
      PopupMenuItem<_OpenChoice>(
        value: value,
        height: 36,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.text.secondary),
            const SizedBox(width: TpSpacing.s12),
            Text(
              label,
              style: TpTypography.body
                  .toTextStyle()
                  .copyWith(color: theme.text.primary),
            ),
          ],
        ),
      );

  final _OpenChoice? picked = await showMenu<_OpenChoice>(
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
    items: <PopupMenuEntry<_OpenChoice>>[
      entry(const _OpenChoice(null), TpIcons.externalLink,
          l10n.detailOpenDefault),
      if (editors.isNotEmpty) const PopupMenuDivider(height: 9),
      for (final ScriptEditor editor in editors)
        entry(_OpenChoice(editor), TpIcons.code, editor.label),
    ],
  );
  if (picked == null || !context.mounted) return;
  final ScriptEditor? editor = picked.editor;
  if (editor == null) {
    await openScriptWithDefaultApp(context, path);
    return;
  }
  final bool ok = await openPathWithEditor(editor, path);
  if (!ok && context.mounted) {
    TpToastHost.show(
      context,
      TpToast(message: l10n.detailOpenFailed, kind: TpStateKind.critical),
    );
  }
}

/// One entry in the Open with menu; a null [editor] is the default app.
///
/// Wrapped because `showMenu` returns null for "dismissed", so a bare
/// `ScriptEditor?` could not also mean "default app".
class _OpenChoice {
  const _OpenChoice(this.editor);

  final ScriptEditor? editor;
}
