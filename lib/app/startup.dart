// The app-level startup sequence that runs after the first frame.
//
// Ports the tail of `src/main.c`: after the windows exist, it spawned
// `check_update_thread` (a background update check) and brought up the taskbar
// bars (`bars_create_all`). Everything else `wWinMain` did — the single-instance
// mutex, config load, i18n and the message loop — is handled elsewhere:
//
//   single instance  lib/core/app/single_instance.dart  (called from main())
//   config load      ConfigRepository.load()            (called from main())
//   i18n             flutter_localizations + AppLocalizations
//   bars             lib/core/bar/bar_controller.dart   (this file starts it)
//   message loop     the Flutter engine
//
// So this file owns two things: starting the update loop, and starting the bar
// controller — both once the UI is up, so anything they raise has somewhere to
// appear.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app/app_providers.dart';
import '../core/bar/bar_controller.dart';

/// Delay between the first frame and the start of the bars and the updater.
const Duration kStartupDelay = Duration(milliseconds: 300);

/// Wraps the app content and starts the post-first-frame work.
///
/// A widget rather than a plain call in `main()` because the update presenter
/// shows a dialog through [appNavigatorKey], which has no context until the
/// first frame has been built.
class AppStartup extends ConsumerStatefulWidget {
  const AppStartup({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends ConsumerState<AppStartup> {
  @override
  void initState() {
    super.initState();
    // Defer to after the first frame so the navigator has a context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The native window is shown once the first frame is rendered. Start the
      // bars and the updater a little later, so engine start-up and the taskbar
      // calls do not sit in front of the first paint. One extra frame repaints
      // the window after it becomes visible.
      WidgetsBinding.instance.scheduleForcedFrame();
      _deferred = Timer(kStartupDelay, () {
        if (!mounted) return;
        _startBars();
        _startUpdateLoop();
      });
    });
  }

  Timer? _deferred;

  @override
  void dispose() {
    _deferred?.cancel();
    super.dispose();
  }

  /// Bring up the taskbar bars.
  ///
  /// Reading `barHostProvider` is what builds `barControllerProvider`: a
  /// `NotifierProvider` nothing watches is never constructed at all, so without
  /// this the bars would exist only while a page that happened to watch them
  /// was on screen. Reading it once here keeps them alive for the app's
  /// lifetime, exactly as `bars_create_all()` was called once from `wWinMain`.
  void _startBars() {
    ref.read(barHostProvider);
  }

  void _startUpdateLoop() {
    final service = ref.read(updateServiceProvider);
    // The loop runs until the user declines, an update is applied, or the
    // process exits. Nothing awaits it; a failure inside is already a value
    // (checkOnce never throws), but guard the unawaited future anyway so a
    // surprise cannot become an unhandled-error crash.
    service.run().catchError((Object e) {
      // A failed update check is not worth interrupting the user over; the next
      // 30-minute tick will try again.
      debugPrint('update loop stopped: $e');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
