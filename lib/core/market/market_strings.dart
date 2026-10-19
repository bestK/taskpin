// User-facing strings for the market, update and elevate flows.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS EXISTS INSTEAD OF `AppLocalizations`
// ─────────────────────────────────────────────────────────────────────────────
// The ARB files are GENERATED (`tool/migrate_lang.py` writes `lib/l10n/app_*.arb`
// from `lang/*.json`) and are read-only for this phase. `flutter gen-l10n` has
// never run in this working copy — there is no `.dart_tool/`, so there is no
// `AppLocalizations` class to import. The UI therefore cannot depend on it yet.
//
// The design is an INTERFACE per flow, with the const en/zh copies behind it.
// When gen-l10n lands, a `_L10nMarketStrings implements MarketStrings` that
// forwards to `AppLocalizations` is a mechanical addition and every widget call
// site is unchanged.
//
// The values below are copied VERBATIM from `lib/l10n/app_en.arb` /
// `lib/l10n/app_zh.arb` (which are themselves generated from `lang/*.json`), so
// the wording is identical to the shipping product.
// `test/market/strings_parity_test.dart` reads the ARB and asserts every field
// here still equals its ARB value — that is the guard against drift while the
// two sources of truth coexist.
//
// ─────────────────────────────────────────────────────────────────────────────
// ARB KEYS THAT ARE MISSING (reported, NOT invented)
// ─────────────────────────────────────────────────────────────────────────────
// Six strings this UI needs have no key in `lang/*.json` and therefore none in
// the ARB. They are listed in [kMissingArbKeys] and the parity test asserts they
// are still ABSENT, so the list cannot silently go stale. The ARB set is
// extended in Phase 11/12 by whoever owns the i18n migration; until then the
// English fallback below is used and is clearly marked.
//
// Pure Dart. No Flutter.

/// The market screen's strings.
abstract class MarketStrings {
  /// Const-constructible so the en/zh implementations can be `const`.
  const MarketStrings();

  String get title;
  String get add;
  String get del;
  String get refresh;
  String get download;
  String get initialStatus;
  String get colName;
  String get colDescription;
  String get colAuthor;
  String get colVersion;
  String get fetching;
  String get selectScriptFirst;
  String get downloading;
  String get downloadFailed;
  String get downloadSuccess;
  String get saveFailed;
  String get maxSources;
  String get enterRepo;
  String get sourceDeleted;
  String get downloadScriptFailed;
  String get install;
  String get viewCode;
  String get cancel;
  String get installPrompt;
  String get overwriteTitle;

  /// `market.script_count` — `"%d scripts"` / `"共 %d 个脚本"`.
  ///
  /// One of the five printf-style keys (`test/l10n/l10n_parity_test.dart`), so
  /// gen-l10n emits a plain String getter and the call site formats it. Use
  /// [scriptCount] rather than touching this directly.
  String get scriptCountTemplate;

  /// `market.overwrite_confirm` — `'Script "%s" already exists. Overwrite?'`.
  /// Another printf key; use [overwriteConfirm] instead.
  String get overwriteConfirmTemplate;

  /// `market.script_count` with the count substituted.
  String scriptCount(int count) =>
      scriptCountTemplate.replaceFirst('%d', '$count');

  /// `market.overwrite_confirm` with the filename substituted.
  String overwriteConfirm(String file) =>
      overwriteConfirmTemplate.replaceFirst('%s', file);

  /// NOT IN THE ARB. A search-field placeholder. Falls back to English.
  String get searchHint;

  /// NOT IN THE ARB. The "already installed" badge on a market card.
  String get installedBadge;

  /// NOT IN THE ARB. The heading above the source list.
  String get sourcesLabel;

  /// NOT IN THE ARB. Shown when a repo has no `manifest.json` and the list came
  /// from the contents API.
  String get viaApiHint;

  /// NOT IN THE ARB. The add-source field's placeholder.
  String get sourcePlaceholder;

  /// NOT IN THE ARB. Shown when the item list is full and the download could not
  /// be added as an item (the secondary bug fixed in `market_installer.dart`).
  String itemLimitReached(int max);
}

/// English market strings. Values copied from `lib/l10n/app_en.arb`.
///
/// `extends` rather than `implements`: [MarketStrings.scriptCount] and
/// [MarketStrings.overwriteConfirm] are concrete convenience wrappers on the
/// interface and must be inherited, not re-declared per locale.
class MarketStringsEn extends MarketStrings {
  const MarketStringsEn();

  @override
  String get title => 'Plugin Market';
  @override
  String get add => 'Add';
  @override
  String get del => 'Del';
  @override
  String get refresh => 'Refresh';
  @override
  String get download => 'Download';
  @override
  String get initialStatus => 'Select a source and click Refresh';
  @override
  String get colName => 'Name';
  @override
  String get colDescription => 'Description';
  @override
  String get colAuthor => 'Author';
  @override
  String get colVersion => 'Version';
  @override
  String get fetching => 'Fetching...';
  @override
  String get scriptCountTemplate => '%d scripts';
  @override
  String get selectScriptFirst => 'Please select a script first';
  @override
  String get downloading => 'Downloading...';
  @override
  String get downloadFailed => 'Download failed';
  @override
  String get downloadSuccess => 'Downloaded and added successfully!';
  @override
  String get saveFailed => 'Save failed';
  @override
  String get maxSources => 'Maximum 8 sources supported';
  @override
  String get enterRepo => 'Enter repository in the dropdown\nFormat: user/repo';
  @override
  String get sourceDeleted => 'Source deleted';
  @override
  String get downloadScriptFailed => 'Failed to download script';
  @override
  String get install => 'Install';
  @override
  String get viewCode => 'View Code';
  @override
  String get cancel => 'Cancel';
  @override
  String get installPrompt => 'Install this script?';
  @override
  String get overwriteConfirmTemplate => 'Script "%s" already exists. Overwrite?';
  @override
  String get overwriteTitle => 'TaskPin - Overwrite';

  @override
  String get searchHint => 'Search scripts';
  @override
  String get installedBadge => 'Installed';
  @override
  String get sourcesLabel => 'Sources';
  @override
  String get viaApiHint => 'This repository has no manifest.json; listing .lua files.';
  @override
  String get sourcePlaceholder => 'user/repo';
  @override
  String itemLimitReached(int max) =>
      'Downloaded, but the item list is full ($max). Add it manually.';
}

/// Chinese market strings. Values copied from `lib/l10n/app_zh.arb`.
class MarketStringsZh extends MarketStrings {
  const MarketStringsZh();

  @override
  String get title => '插件市场';
  @override
  String get add => '添加';
  @override
  String get del => '删除';
  @override
  String get refresh => '刷新';
  @override
  String get download => '下载';
  @override
  String get initialStatus => '选择源后点击刷新';
  @override
  String get colName => '名称';
  @override
  String get colDescription => '描述';
  @override
  String get colAuthor => '作者';
  @override
  String get colVersion => '版本';
  @override
  String get fetching => '正在获取...';
  @override
  String get scriptCountTemplate => '共 %d 个脚本';
  @override
  String get selectScriptFirst => '请先选择一个脚本';
  @override
  String get downloading => '正在下载...';
  @override
  String get downloadFailed => '下载失败';
  @override
  String get downloadSuccess => '下载并添加成功！';
  @override
  String get saveFailed => '保存失败';
  @override
  String get maxSources => '最多支持 8 个源';
  @override
  String get enterRepo => '请在下拉框中输入仓库地址\n格式：user/repo';
  @override
  String get sourceDeleted => '已删除源';
  @override
  String get downloadScriptFailed => '脚本下载失败';
  @override
  String get install => '安装';
  @override
  String get viewCode => '查看代码';
  @override
  String get cancel => '取消';
  @override
  String get installPrompt => '是否安装此脚本？';
  @override
  String get overwriteConfirmTemplate => '脚本 "%s" 已存在，是否覆盖？';
  @override
  String get overwriteTitle => 'TaskPin - 覆盖确认';

  @override
  String get searchHint => '搜索脚本';
  @override
  String get installedBadge => '已安装';
  @override
  String get sourcesLabel => '源';
  @override
  String get viaApiHint => '该仓库没有 manifest.json，改为列出 .lua 文件。';
  @override
  String get sourcePlaceholder => 'user/repo';
  @override
  String itemLimitReached(int max) => '已下载，但条目已达上限（$max），请手动添加。';
}

/// The update flow's strings.
abstract class UpdateStrings {
  /// Const-constructible so the en/zh implementations can be `const`.
  const UpdateStrings();

  /// `bar.update_available` — `'New version v%s available. Download?'`.
  ///
  /// NOTE: this key carries only ONE placeholder, but the shipping C message is
  /// `"New version v%s available (current: v1.6.8)\n\nUpdate now?"`
  /// (`lib/update.c:150`) — it shows both versions. The two-argument variant is
  /// listed in [kMissingArbKeys] as `update.available_with_current`. Until that
  /// key exists, [updateAvailable] composes the full message from this template
  /// plus a parenthetical, so no information is lost.
  String get updateAvailableTemplate;

  /// `bar.up_to_date`.
  String get upToDate;

  /// `bar.update_failed`.
  String get updateFailed;

  /// `bar.check_update`.
  String get checkUpdate;

  /// NOT IN THE ARB. The update prompt with both versions, matching the current
  /// binary's wording exactly.
  String updateAvailable(String remote, String current);

  /// NOT IN THE ARB. Shown while the new build downloads.
  String get downloadingUpdate;

  /// NOT IN THE ARB. Shown after the batch has been launched and before exit.
  String get restartingToUpdate;

  /// NOT IN THE ARB. macOS: the bundle is not writable, so we open the release
  /// page instead of replacing in place.
  String get bundleNotWritable;
}

class UpdateStringsEn implements UpdateStrings {
  const UpdateStringsEn();

  @override
  String get updateAvailableTemplate => 'New version v%s available. Download?';
  @override
  String get upToDate => 'Already up to date.';
  @override
  String get updateFailed => 'Failed to check for updates.';
  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String updateAvailable(String remote, String current) =>
      'New version v$remote available (current: v$current)\n\nUpdate now?';

  @override
  String get downloadingUpdate => 'Downloading update...';
  @override
  String get restartingToUpdate => 'Restarting to finish the update...';
  @override
  String get bundleNotWritable =>
      'The application folder is not writable. Opening the download page instead.';
}

class UpdateStringsZh implements UpdateStrings {
  const UpdateStringsZh();

  @override
  String get updateAvailableTemplate => '发现新版本 v%s，是否下载？';
  @override
  String get upToDate => '已是最新版本。';
  @override
  String get updateFailed => '检查更新失败。';
  @override
  String get checkUpdate => '检查更新';

  @override
  String updateAvailable(String remote, String current) =>
      '发现新版本 v$remote（当前 v$current）\n\n是否立即更新？';

  @override
  String get downloadingUpdate => '正在下载更新...';
  @override
  String get restartingToUpdate => '正在重启以完成更新...';
  @override
  String get bundleNotWritable => '应用目录不可写，改为打开下载页面。';
}

/// The elevate flow's strings. All four keys exist in the ARB.
abstract class ElevateStrings {
  /// Const-constructible so the en/zh implementations can be `const`.
  const ElevateStrings();

  /// `elevate.blocked` — `'⚠️ Admin required'` / `'⚠️ 需要管理员权限'`.
  /// What the taskbar bar shows when a script needs admin.
  String get blocked;

  /// `elevate.desc_default` — `'This script requires administrator privileges'`.
  String get descDefault;

  /// `elevate.restart_confirm` — `'Restart TaskPin as administrator?'`.
  /// The confirm dialog's body text.
  String get restartConfirm;

  /// `elevate.dialog_title` — `'TaskPin - Admin Required'`.
  String get dialogTitle;

  /// NOT IN THE ARB. Shown when the user dismisses the UAC prompt
  /// (`ERROR_CANCELLED`, 1223).
  String get cancelled;

  /// NOT IN THE ARB. Shown when the relaunch could not be started at all.
  String get failed;
}

class ElevateStringsEn implements ElevateStrings {
  const ElevateStringsEn();

  @override
  String get blocked => '⚠️ Admin required';
  @override
  String get descDefault => 'This script requires administrator privileges';
  @override
  String get restartConfirm => 'Restart TaskPin as administrator?';
  @override
  String get dialogTitle => 'TaskPin - Admin Required';
  @override
  String get cancelled => 'Administrator permission was declined.';
  @override
  String get failed => 'Could not restart as administrator.';
}

class ElevateStringsZh implements ElevateStrings {
  const ElevateStringsZh();

  @override
  String get blocked => '⚠️ 需要管理员权限';
  @override
  String get descDefault => '此脚本需要管理员权限';
  @override
  String get restartConfirm => '是否以管理员身份重启 TaskPin？';
  @override
  String get dialogTitle => 'TaskPin - 需要管理员权限';
  @override
  String get cancelled => '已取消管理员授权。';
  @override
  String get failed => '无法以管理员身份重启。';
}

/// Strings this phase needs that have NO key in `lang/*.json` / the ARB.
///
/// Reported rather than invented: `lang/*.json` and `lib/l10n/app_*.arb` are
/// read-only for this phase, and the ARB set is extended in Phase 11/12 by the
/// i18n owner. `test/market/strings_parity_test.dart` asserts every key here is
/// still ABSENT from the ARB, so when one gets added the test fails and tells
/// us to swap the fallback for the real getter.
const List<String> kMissingArbKeys = <String>[
  // The update prompt needs TWO values; `barUpdateAvailable` has one.
  'update.available_with_current',
  'update.downloading',
  'update.restarting',
  'update.bundle_not_writable',
  'market.search_hint',
  'market.installed_badge',
  'market.sources_label',
  'market.via_api_hint',
  'market.source_placeholder',
  'market.item_limit_reached',
  'elevate.cancelled',
  'elevate.failed',
];
