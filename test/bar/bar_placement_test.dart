// The auto-tiling index/offset rule, and the wire that carries it.
//
// The bug this covers: bar ids are config item indices, and the native side
// used to tile by CREATION order. Reordering items therefore left every bar at
// its old slot (wrong content, overlapping widths), and unpinning left a hole.
// The fix sends an explicit `autoIndex` (the index among PINNED items) over
// `taskpin/bar`, which native sorts by. These tests pin down:
//
//   * the ordering key, so `moveItem` renumbers it consistently;
//   * the offset accumulator (`width + 2`), which is what makes widths add up;
//   * that explicit bars are excluded from tiling but still numbered in the
//     pinned sequence;
//   * that the wire actually carries `autoIndex`.
//
// Pure Dart: no engine, no taskbar, no channel handler.

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/bar/bar_channel.dart';
import 'package:taskpin/core/bar/bar_controller.dart';
import 'package:taskpin/core/config/config_schema.dart';

PinItem _item(
  String name, {
  bool pinned = true,
  int barWidth = 0,
  int barX = -1,
}) => PinItem(name: name, pinned: pinned, barWidth: barWidth, barX: barX);

TaskPinConfig _config(List<PinItem> items, {int width = 320}) =>
    TaskPinConfig(items: items, width: width);

void main() {
  group('computeBarPlacements', () {
    test('auto bars are numbered by pinned order and tile by width + 2', () {
      final TaskPinConfig cfg = _config(<PinItem>[
        _item('a', barWidth: 100),
        _item('b', barWidth: 200),
        _item('c', barWidth: 50),
      ]);

      final List<BarPlacement> ps = computeBarPlacements(cfg);

      expect(ps.map((BarPlacement p) => p.itemIndex), <int>[0, 1, 2]);
      expect(ps.map((BarPlacement p) => p.autoIndex), <int>[0, 1, 2]);
      expect(ps.map((BarPlacement p) => p.width), <int>[100, 200, 50]);
      // x is native's business for auto bars.
      expect(ps.every((BarPlacement p) => p.x == -1), isTrue);
      // 0, 100+2, 100+2+200+2
      expect(ps.map((BarPlacement p) => p.offset), <int>[0, 102, 304]);
    });

    test('bar_width 0 falls back to the global width', () {
      final TaskPinConfig cfg = _config(
        <PinItem>[_item('a'), _item('b')],
        width: 150,
      );

      final List<BarPlacement> ps = computeBarPlacements(cfg);
      expect(ps.map((BarPlacement p) => p.width), <int>[150, 150]);
      expect(ps.map((BarPlacement p) => p.offset), <int>[0, 152]);
    });

    test('unpinned items get no bar and take no offset', () {
      final TaskPinConfig cfg = _config(<PinItem>[
        _item('a', barWidth: 100),
        _item('hidden', pinned: false, barWidth: 500),
        _item('b', barWidth: 100),
      ]);

      final List<BarPlacement> ps = computeBarPlacements(cfg);

      expect(ps.map((BarPlacement p) => p.itemIndex), <int>[0, 2]);
      // The pinned sequence skips the hidden item...
      expect(ps.map((BarPlacement p) => p.autoIndex), <int>[0, 1]);
      // ...and so does the offset: no hole where it was.
      expect(ps.map((BarPlacement p) => p.offset), <int>[0, 102]);
    });

    test('explicit bars keep their x and are excluded from the tiling', () {
      final TaskPinConfig cfg = _config(<PinItem>[
        _item('auto-a', barWidth: 100),
        _item('pinned-here', barWidth: 60, barX: 400),
        _item('auto-b', barWidth: 100),
      ]);

      final List<BarPlacement> ps = computeBarPlacements(cfg);

      expect(ps[1].isAuto, isFalse);
      expect(ps[1].x, 400);
      expect(ps[1].autoIndex, -1);
      // Explicit bars do not push the auto ones along.
      expect(ps[2].offset, 102);
      // But they still occupy a slot in the pinned sequence.
      expect(ps[2].autoIndex, 2);
    });

    test('a reorder changes the ordering key, not the set', () {
      final List<PinItem> items = <PinItem>[
        _item('a', barWidth: 100),
        _item('b', barWidth: 200),
        _item('c', barWidth: 50),
      ];
      final TaskPinConfig cfg = _config(items);

      // What ConfigNotifier.moveItem(0, 2) does: removeAt + insert.
      final PinItem moved = items.removeAt(0);
      items.insert(2, moved);

      final List<BarPlacement> ps = computeBarPlacements(cfg);

      // The ids moved with their items, so the ordering key follows the new
      // config order — that is what makes the taskbar order change.
      expect(ps.map((BarPlacement p) => p.itemIndex), <int>[0, 1, 2]);
      expect(ps.map((BarPlacement p) => p.autoIndex), <int>[0, 1, 2]);
      expect(ps.map((BarPlacement p) => p.width), <int>[200, 50, 100]);
      // Offsets are recomputed from the new widths: b, c, a.
      expect(ps.map((BarPlacement p) => p.offset), <int>[0, 202, 254]);
    });

    test('the bar cap truncates and keeps the first pinned items', () {
      final List<PinItem> many = <PinItem>[
        for (int i = 0; i < ConfigLimits.maxBars + 3; i++)
          _item('item$i', barWidth: 10),
      ];

      final List<BarPlacement> ps = computeBarPlacements(_config(many));

      expect(ps.length, ConfigLimits.maxBars);
      expect(ps.last.itemIndex, ConfigLimits.maxBars - 1);
      expect(ps.last.autoIndex, ConfigLimits.maxBars - 1);
    });

    test('placementFor finds a pinned item and returns null otherwise', () {
      final TaskPinConfig cfg = _config(<PinItem>[
        _item('a'),
        _item('hidden', pinned: false),
      ]);

      expect(placementFor(cfg, 0)?.itemIndex, 0);
      expect(placementFor(cfg, 1), isNull);
      expect(placementFor(cfg, 99), isNull);
    });
  });

  group('the wire carries autoIndex', () {
    test('RecordingBarApi records the key for both methods', () async {
      final RecordingBarApi api = RecordingBarApi();
      await api.setSpans(3, const <Map<String, dynamic>>[], autoIndex: 1);
      await api.setGeometry(4, width: 100, x: -1, autoIndex: 2);
      await api.setGeometry(5, width: 100, x: 400, autoIndex: -1);

      expect(api.calls, <String>[
        'setSpans(3,w=0,x=-1,a=1,n=0)',
        'setGeometry(4,100,-1,a=2)',
        'setGeometry(5,100,400,a=-1)',
      ]);
      await api.dispose();
    });

    test('BarGeometrySnapshot equality includes the placement mode', () {
      const BarGeometrySnapshot auto =
          BarGeometrySnapshot(width: 100, x: -1, autoIndex: 0);
      const BarGeometrySnapshot explicit =
          BarGeometrySnapshot(width: 100, x: -1);

      expect(auto == explicit, isFalse);
      expect(auto.isAuto, isTrue);
      expect(explicit.isAuto, isFalse);
    });
  });
}
