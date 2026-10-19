// Application-level providers: the running build's version, the updater, and
// the confirm presenter the updater asks through.
//
// Phase 11 (`docs/FLUTTER_REWRITE_PLAN.md`) requires the updater to check on
// launch and every 30 minutes, compare versions, ask the user, and apply. The
// service itself (`core/update/update_service.dart`) is pure Dart with every
// side effect injected; this file supplies the production dependencies and the
// UI presenter, and `lib/app/startup.dart` drives the loop.
//
// The version comparison is deliberately a STRING compare, not semver — see
// `core/update/version_compare.dart`. Existing installs depend on it, and
// `test/update/version_compare_test.dart` pins it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../market/geo_providers.dart';
import '../net/http_providers.dart';
import '../update/update_models.dart';
import '../update/update_service.dart';

/// The version baked into the build, from the `TASKPIN_VERSION` define.
///
const String kBuildVersion =
    String.fromEnvironment('TASKPIN_VERSION', defaultValue: '1.6.8');

/// The running build's version.
///
/// The Makefile bakes the same value into the C build via
/// `-DTASKPIN_VERSION="$(VERSION)"` from `version.txt`; the updater compares the
/// remote `version.txt` against this with `strcmp`.
final Provider<String> appVersionProvider = Provider<String>((Ref ref) {
  // Prefer `version.txt` next to the executable when it is present (a portable
  // install ships it), so a hand-updated install reports correctly. Fall back to
  // the compile-time constant, which is what a packaged build has.
  try {
    final File f = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}version.txt',
    );
    if (f.existsSync()) {
      final String v = f.readAsStringSync().trim();
      if (v.isNotEmpty) return v;
    }
  } catch (_) {
    // Fall through to the compile-time constant.
  }
  return kBuildVersion;
});

/// The navigator key the update presenter shows dialogs through.
///
/// A global key is the standard way to raise a dialog from outside the widget
/// tree — the updater loop is not a widget and cannot hold a `BuildContext`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Asks the user whether to install an update, using the design system's confirm
/// dialog. Mirrors the C `MessageBoxW(..., MB_YESNO | MB_ICONINFORMATION)`.
class TpUpdatePresenter extends UpdatePresenter {
  const TpUpdatePresenter(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;

  @override
  Future<bool> confirmUpdate(String remote, String current) async {
    final BuildContext? ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      // No UI to ask through. Decline rather than update silently.
      return false;
    }
    final AppLocalizations l10n = ctx.l10n;
    final bool? ok = await TpConfirmDialog.show(
      ctx,
      title: l10n.updateAvailableTitle,
      message: l10n.updateAvailableMessage(remote, current),
      detail: l10n.updateAvailableDetail,
      confirmLabel: l10n.updateConfirm,
      cancelLabel: l10n.updateLater,
    );
    return ok == true;
  }

  @override
  void onPhase(UpdatePhase phase) {
    // The download/restart phases are quick and the app is about to exit; a
    // toast here would be gone before it is read. Left as a no-op.
  }
}

/// The confirm presenter, as a provider so tests can override it.
final Provider<UpdatePresenter> updatePresenterProvider =
    Provider<UpdatePresenter>((Ref ref) => TpUpdatePresenter(appNavigatorKey));

/// The live updater.
///
/// `allowRealApply` is left to the service's own default, which refuses to
/// replace the binary unless the process is a packaged build (so a `dart run`
/// or a test can never overwrite the running executable).
final Provider<UpdateService> updateServiceProvider = Provider<UpdateService>((Ref ref) {
  return UpdateService(
    fetcher: ref.watch(httpFetcherProvider),
    currentVersion: ref.watch(appVersionProvider),
    geo: ref.watch(geoLocatorProvider),
    presenter: ref.watch(updatePresenterProvider),
  );
});
