// The macOS strip menu: a bare right-click asks Dart for the menu, and the
// chosen item comes back as a tag that carries both the bar and the action.
//
// Windows resolves its menu natively and sends `onContextMenu` WITH an
// `action`; that path must keep decoding exactly as before.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/bar/bar_channel.dart';

BarEvent? _decode(String method, Map<String, Object?> args) =>
    BarEvent.fromMethodCall(MethodCall(method, args));

void main() {
  test('a right-click without an action asks for the menu', () {
    final BarEvent? e = _decode('onContextMenu', <String, Object?>{'barId': 3});
    expect(e, isA<BarMenuRequestEvent>());
    expect(e!.barId, 3);
  });

  test('a Windows right-click with an action still resolves directly', () {
    final BarEvent? e = _decode(
      'onContextMenu',
      <String, Object?>{'barId': 2, 'action': 'exit'},
    );
    expect(e, isA<BarContextMenuEvent>());
    expect((e! as BarContextMenuEvent).action, BarMenuAction.exit);
    expect(e.barId, 2);
  });

  test('a menu selection tag round-trips bar and action', () {
    for (final BarMenuAction a in BarMenuAction.values) {
      for (final int bar in <int>[0, 1, 7, 15]) {
        final BarEvent? e = _decode(
          'onContextMenuSelection',
          <String, Object?>{'tag': a.tagFor(bar)},
        );
        expect(e, isA<BarContextMenuEvent>(), reason: '$a bar $bar');
        expect((e! as BarContextMenuEvent).action, a);
        expect(e.barId, bar);
      }
    }
  });

  test('an unknown tag is dropped, not read as unpin', () {
    expect(_decode('onContextMenuSelection', <String, Object?>{'tag': 7}), isNull);
    expect(_decode('onContextMenuSelection', <String, Object?>{'tag': -1}), isNull);
    expect(_decode('onContextMenuSelection', <String, Object?>{}), isNull);
  });
}
