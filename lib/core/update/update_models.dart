// Result types for the updater.
//
// Separated from `update_service.dart` so the UI can import the vocabulary
// without pulling in `dart:io`.
//
// Pure Dart.

/// What a single update check found.
enum UpdateStatus {
  /// The remote version sorts after the local one (string compare).
  available,

  /// Equal, or the remote sorts before the local one.
  upToDate,

  /// The check itself failed: transport failure, non-2xx, or an empty body.
  checkFailed,
}

/// The result of one check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.remoteVersion,
    required this.currentVersion,
    this.inChina = false,
  });

  final UpdateStatus status;

  /// The trimmed remote version, or `''` when the check failed.
  final String remoteVersion;

  /// The running build's version.
  final String currentVersion;

  /// Whether the check went through the gh-proxy mirror. Surfaced so the UI can
  /// explain a slow or failed check.
  final bool inChina;

  bool get isAvailable => status == UpdateStatus.available;

  @override
  String toString() =>
      'UpdateCheckResult(${status.name}, remote: "$remoteVersion", current: "$currentVersion")';
}

/// What applying an update did (or could not do).
enum UpdateApplyStatus {
  /// The replacement was staged and the process is about to exit. Windows: the
  /// detached batch was launched. macOS: the bundle was replaced and `open` was
  /// invoked.
  restarting,

  /// The download failed; the release page was opened instead
  /// (`lib/update.c:73-82`).
  downloadFailed,

  /// macOS only: the `.app` bundle is not writable, so the release page was
  /// opened rather than replacing in place.
  bundleNotWritable,

  /// No supported apply path for this platform; the release page was opened.
  openedBrowser,

  /// Applying was refused because this process is not a packaged build. The
  /// guard that stops a test run from replacing the binary under it.
  disabled,

  /// `apply` was called twice.
  alreadyApplied,
}

/// The result of an apply attempt.
class UpdateApplyResult {
  const UpdateApplyResult({required this.status, this.detail = ''});

  final UpdateApplyStatus status;

  /// A diagnostic detail. Not user-facing.
  final String detail;

  /// True when the process is expected to exit and come back updated.
  bool get isRestarting => status == UpdateApplyStatus.restarting;

  @override
  String toString() => 'UpdateApplyResult(${status.name}${detail.isEmpty ? '' : ', $detail'})';
}

/// Progress phases the presenter is told about.
enum UpdatePhase {
  checking,
  downloading,
  restarting,
}
