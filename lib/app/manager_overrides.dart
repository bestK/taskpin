// The provider overrides `main.dart` installs around the app.
//
// Extracted so an end-to-end test can build the SAME tree the app ships. A
// test that repeats the override list would drift from it the moment an
// override is added, and then pass while the app is broken.
//
// What stays in `main.dart`: the single-instance mutex, config path resolution,
// and `runApp` — the three things a test must not inherit.

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_engine/taskpin_engine.dart' as engine;

import '../app/windows/dialog_window.dart';
import '../core/bar/bar_controller.dart';
import '../core/config/config_providers.dart';
import '../core/config/config_repository.dart';
import '../core/config/config_schema.dart';
import '../features/dialogs/dialog_spec.dart';
import '../features/dialogs/dialog_spec_bridge.dart';

/// Build the override list for the manager window.
///
/// [dialogHost] / [exitRequest] / [urlOpener] are optional because a widget
/// test wants none of them: leaving one out means the corresponding seam stays
/// null, and the controller's null checks make the effect a no-op.
List<Override> managerOverrides({
  required ConfigRepository repository,
  required TaskPinConfig config,
  DialogWindowHost? dialogHost,
  VoidCallback? exitRequest,
  VoidCallback? managerRaiser,
  Future<void> Function(String url)? urlOpener,
}) =>
    <Override>[
      configRepositoryProvider.overrideWithValue(repository),
      initialConfigProvider.overrideWithValue(config),
      if (exitRequest != null)
        exitRequestProvider.overrideWithValue(exitRequest),
      if (managerRaiser != null)
        managerRaiserProvider.overrideWithValue(managerRaiser),
      if (dialogHost != null)
        dialogOpenerProvider.overrideWithValue(
          (engine.DialogSpec spec, String luaPath) {
            final DialogSpec? uiSpec = uiSpecFromEngine(spec);
            if (uiSpec == null) return;
            unawaited(dialogHost.open(uiSpec, luaPath: luaPath));
          },
        ),
      if (urlOpener != null) urlOpenerProvider.overrideWithValue(urlOpener),
    ];
