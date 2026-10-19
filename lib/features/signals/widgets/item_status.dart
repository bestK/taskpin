// Derived status for one signal.
//
// The plan's bar language has four states — running / stale / error / paused —
// and `TpBarState` (taskpin_design) already models them. The management list
// needs the same vocabulary, so this file maps a `PinItem` plus what we can know
// about it to a `TpStateKind`.
//
// ---------------------------------------------------------------------------
// WHAT THIS CAN AND CANNOT KNOW (Phase 5)
// ---------------------------------------------------------------------------
// There is no engine in Dart yet (Phase 3 owns the FFI bridge), so there is no
// live "last run" or error text. This file therefore reports the states that are
// knowable from the config and the filesystem — a missing script, a URL item
// with no URL, a pinned item — and marks everything else `neutral` rather than
// inventing a healthy-looking green dot.
//
// That is deliberate: a green "running" dot that is not backed by a real result
// is worse than no dot, because it teaches the user to trust it. Once Phase 3
// lands, `ScriptResult` feeds `lastUpdated`/`error` and the `neutral` fallbacks
// become real states.
//
// Pure Dart (`dart:io` only) so the classification rules are unit-testable
// without a Flutter SDK.

import 'dart:io';

import '../../../../core/config/config_schema.dart';

/// Why a project is in the state it is in. The UI maps it to text so the dot is
/// never the only carrier of meaning.
enum SignalStatusReason {
  /// A Lua item whose script file does not exist on disk.
  scriptMissing,

  /// A Lua item whose `lua_path` is empty.
  scriptUnset,

  /// A URL item with no URL.
  urlUnset,

  /// Configured and pinned: it should be on the taskbar.
  pinned,

  /// Configured but not pinned.
  notPinned,
}

/// The derived status of one item.
class SignalStatus {
  const SignalStatus({
    required this.kind,
    required this.reason,
    this.detail,
  });

  /// The design system's state vocabulary. `neutral` means "nothing is wrong,
  /// and nothing is claimed".
  final TpStateKindLike kind;

  final SignalStatusReason reason;

  /// Extra detail, e.g. the missing path. Null when the reason says it all.
  final String? detail;

  /// Whether the item can plausibly run.
  bool get isRunnable =>
      reason != SignalStatusReason.scriptMissing &&
      reason != SignalStatusReason.scriptUnset &&
      reason != SignalStatusReason.urlUnset;

  /// Classify [item].
  ///
  /// [pathExists] is injectable so tests need no filesystem.
  static SignalStatus of(
    PinItem item, {
    bool Function(String path)? pathExists,
  }) {
    final bool Function(String) exists = pathExists ?? _fileExists;

    if (item.type == PinItemType.lua) {
      final String path = item.luaPath.trim();
      if (path.isEmpty) {
        return const SignalStatus(
          kind: TpStateKindLike.danger,
          reason: SignalStatusReason.scriptUnset,
        );
      }
      if (!exists(path)) {
        return SignalStatus(
          kind: TpStateKindLike.danger,
          reason: SignalStatusReason.scriptMissing,
          detail: path,
        );
      }
    } else if (item.url.trim().isEmpty) {
      return const SignalStatus(
        kind: TpStateKindLike.danger,
        reason: SignalStatusReason.urlUnset,
      );
    }

    return item.pinned
        ? const SignalStatus(
            kind: TpStateKindLike.success,
            reason: SignalStatusReason.pinned,
          )
        : const SignalStatus(
            kind: TpStateKindLike.neutral,
            reason: SignalStatusReason.notPinned,
          );
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      // A malformed path (illegal characters, a reserved device name) throws
      // rather than returning false. Treat it as missing.
      return false;
    }
  }
}

/// A local mirror of `TpStateKind`, so this file does not import
/// `package:flutter` (and stays unit-testable without the Flutter SDK).
///
/// `signal_list_tile.dart` maps this to the real `TpStateKind` in one place; a
/// test asserts the two stay in step, so a new state cannot be added to the
/// design system without this file being updated.
enum TpStateKindLike { success, warning, danger, info, neutral }
