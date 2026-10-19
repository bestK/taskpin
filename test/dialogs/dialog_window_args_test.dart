// The dialog-window discriminator.
//
// `desktop_multi_window` starts the child engine on the SAME Dart entry point as
// the manager (`set_dart_entrypoint_arguments(["multi_window", id, argument])`
// in its Windows `FlutterWindow`), so `main` must tell the two apart by the
// window's argument string. The manager window is registered with an EMPTY
// argument string (`AttachFlutterMainWindow`), which is why `decode('')` must
// NOT report a dialog — otherwise the manager would render the dialog UI.

import 'package:taskpin/app/windows/dialog_window.dart';
import 'package:test/test.dart';

void main() {
  group('DialogWindowArguments', () {
    test('the manager window (empty argument) is NOT a dialog', () {
      final DialogWindowArguments a = DialogWindowArguments.decode('');
      expect(a.isDialog, isFalse);
      expect(a.kind, DialogWindowArguments.kUnknownKind);
    });

    test('a dialog argument round-trips', () {
      const DialogWindowArguments original = DialogWindowArguments(
        luaPath: 'scripts/hud.lua',
        argsJson: '{"K":"v"}',
      );
      final DialogWindowArguments a =
          DialogWindowArguments.decode(original.encode());
      expect(a.isDialog, isTrue);
      expect(a.luaPath, 'scripts/hud.lua');
      expect(a.argsJson, '{"K":"v"}');
    });

    test('an unparseable argument is not a dialog', () {
      expect(DialogWindowArguments.decode('not json').isDialog, isFalse);
    });

    test('a JSON object without a kind is not a dialog', () {
      expect(DialogWindowArguments.decode('{"x":1}').isDialog, isFalse);
    });

    test('a dialog with no script has an empty luaPath (refresh disabled)', () {
      final DialogWindowArguments a =
          DialogWindowArguments.decode(const DialogWindowArguments().encode());
      expect(a.isDialog, isTrue);
      expect(a.luaPath, isEmpty);
      expect(a.argsJson, isEmpty);
    });
  });
}
