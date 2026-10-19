// STOPGAP localization generator.
//
// ---------------------------------------------------------------------------
// `flutter gen-l10n` IS THE AUTHORITATIVE GENERATOR. THIS SCRIPT ONLY EXISTS
// BECAUSE THE FLUTTER TOOL COULD NOT RUN.
// ---------------------------------------------------------------------------
//
// In this environment `D:\flutter\bin\cache\flutter_tools.snapshot` did not
// exist (it was still being compiled), so `flutter gen-l10n` was unavailable and
// `lib/l10n/app_localizations*.dart` could not be produced the normal way.
//
// This script reads the same ARB files (`l10n.yaml`: arb-dir `lib/l10n`,
// template `app_en.arb`, output class `AppLocalizations`, `synthetic-package:
// false`) and emits the same three files gen-l10n would, into the same place,
// with the same public API:
//
//   lib/l10n/app_localizations.dart      AppLocalizations (of/delegate/load/…)
//   lib/l10n/app_localizations_en.dart   AppLocalizationsEn
//   lib/l10n/app_localizations_zh.dart   AppLocalizationsZh
//
// It is deliberately THIN: a flat `String get <key> => '<value>';` per key, no
// ICU handling, no plural/select support. That is sufficient because the ARB
// files carry no placeholders gen-l10n would interpret — see the note in
// `l10n.yaml` and the assertion in `test/l10n/l10n_parity_test.dart`, which pins
// exactly five keys as carrying printf-style `%s`/`%d` that the CALL SITE
// formats. Those keys are plain String getters here, exactly as gen-l10n would
// emit them.
//
// HOW TO RETIRE THIS SCRIPT
// -------------------------
// Once `flutter gen-l10n` runs, delete this file. The generated Dart is
// overwritten in place, so nothing else changes: the class name, file names and
// member names are identical. Run `flutter gen-l10n` and diff — a non-empty diff
// means this script drifted and the gen-l10n output wins.
//
// Run with the raw Dart SDK (no Flutter SDK needed, no packages):
//   dart run tool/gen_l10n_fallback.dart
//
// It imports only `dart:convert` and `dart:io`, so it is analysable and
// runnable in this environment.

import 'dart:convert';
import 'dart:io';

const String kArbDir = 'lib/l10n';
const String kTemplateFile = 'app_en.arb';
const String kOutputClass = 'AppLocalizations';
const String kOutputFile = 'app_localizations.dart';

/// Locale code -> ARB file. Order fixes `supportedLocales`, so it is stable.
const Map<String, String> kLocales = <String, String>{
  'en': 'app_en.arb',
  'zh': 'app_zh.arb',
};

Future<void> main(List<String> args) async {
  final Directory dir = Directory(kArbDir);
  if (!dir.existsSync()) {
    stderr.writeln('gen_l10n_fallback: $kArbDir not found. Run from the repo root.');
    exitCode = 1;
    return;
  }

  final Map<String, Map<String, String>> byLocale =
      <String, Map<String, String>>{};
  for (final MapEntry<String, String> e in kLocales.entries) {
    final File f = File('$kArbDir/${e.value}');
    if (!f.existsSync()) {
      stderr.writeln('gen_l10n_fallback: missing ${f.path}');
      exitCode = 1;
      return;
    }
    byLocale[e.key] = _readArb(f);
  }

  // The template defines the key set and the order.
  final Map<String, String> template = byLocale['en']!;
  final List<String> keys = template.keys.toList();

  // Every locale must carry every template key. gen-l10n warns via
  // untranslated-messages-file; a missing key here would be a compile error at
  // the call site, so fail loudly instead.
  final List<String> problems = <String>[];
  for (final MapEntry<String, Map<String, String>> e in byLocale.entries) {
    final Set<String> missing = template.keys.toSet().difference(
          e.value.keys.toSet(),
        );
    final Set<String> extra = e.value.keys.toSet().difference(
          template.keys.toSet(),
        );
    if (missing.isNotEmpty) {
      problems.add('${e.key}: missing ${missing.length} key(s): '
          '${missing.take(5).join(", ")}');
    }
    if (extra.isNotEmpty) {
      problems.add('${e.key}: ${extra.length} key(s) not in the template: '
          '${extra.take(5).join(", ")}');
    }
  }
  if (problems.isNotEmpty) {
    for (final String p in problems) {
      stderr.writeln('gen_l10n_fallback: $p');
    }
    exitCode = 1;
    return;
  }

  final StringBuffer out = StringBuffer();
  for (final MapEntry<String, Map<String, String>> e in byLocale.entries) {
    final String className = '${kOutputClass}${_pascal(e.key)}';
    File('$kArbDir/app_localizations_${e.key}.dart').writeAsStringSync(
      _localeFile(className, e.key, e.value, keys),
      encoding: utf8,
    );
    out.writeln("import 'app_localizations_${e.key}.dart';");
  }

  File('$kArbDir/$kOutputFile').writeAsStringSync(
    _delegateFile(byLocale.keys.toList(), out.toString(), keys),
    encoding: utf8,
  );

  stdout.writeln('gen_l10n_fallback: wrote $kArbDir/$kOutputFile and '
      '${byLocale.length} locale file(s), ${keys.length} keys each.');
  stdout.writeln('  locales: ${byLocale.keys.join(", ")}');
}

/// Reads an ARB, dropping `@@locale` and any other `@`-prefixed metadata key.
Map<String, String> _readArb(File file) {
  final dynamic decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (decoded is! Map) {
    stderr.writeln('gen_l10n_fallback: ${file.path} is not a JSON object');
    exitCode = 1;
    return <String, String>{};
  }
  final Map<String, String> out = <String, String>{};
  for (final MapEntry<dynamic, dynamic> e in decoded.entries) {
    final String key = e.key as String;
    if (key.startsWith('@')) continue;
    if (e.value is! String) {
      stderr.writeln('gen_l10n_fallback: ${file.path}["$key"] is not a String; '
          'this script has no ICU support by design.');
      exitCode = 1;
      continue;
    }
    out[key] = e.value as String;
  }
  return out;
}

String _localeFile(
  String className,
  String locale,
  Map<String, String> values,
  List<String> keys,
) {
  final StringBuffer b = StringBuffer();
  b.writeln('// GENERATED by tool/gen_l10n_fallback.dart — DO NOT EDIT.');
  b.writeln('// `flutter gen-l10n` overwrites this file; see that script for why');
  b.writeln('// this stopgap exists and how to retire it.');
  b.writeln('//');
  b.writeln('// ignore_for_file: type=lint');
  b.writeln();
  b.writeln("import '$kOutputFile';");
  b.writeln();
  b.writeln('/// The $locale strings.');
  b.writeln('class $className extends $kOutputClass {');
  b.writeln('  /// Constructs the $locale strings.');
  b.writeln('  $className([String locale = \'$locale\']) : super(locale);');
  b.writeln();
  for (final String key in keys) {
    b.writeln('  @override');
    b.writeln('  String get $key => ${_dartString(values[key]!)};');
    b.writeln();
  }
  b.writeln('}');
  return b.toString();
}

String _delegateFile(List<String> locales, String imports, List<String> keys) {
  final StringBuffer b = StringBuffer();
  b.writeln('// GENERATED by tool/gen_l10n_fallback.dart — DO NOT EDIT.');
  b.writeln('// `flutter gen-l10n` overwrites this file; see that script for why');
  b.writeln('// this stopgap exists and how to retire it.');
  b.writeln('//');
  b.writeln('// ignore_for_file: type=lint');
  b.writeln();
  b.writeln("import 'dart:async';");
  b.writeln();
  b.writeln("import 'package:flutter/foundation.dart';");
  b.writeln("import 'package:flutter/widgets.dart';");
  b.writeln("import 'package:flutter_localizations/flutter_localizations.dart';");
  b.writeln("import 'package:intl/intl.dart' as intl;");
  b.writeln();
  b.write(imports);
  b.writeln();
  b.writeln('/// Callers can lookup localized strings with an instance of $kOutputClass');
  b.writeln('/// returned by `$kOutputClass.of(context)`.');
  b.writeln('///');
  b.writeln('/// Applications need to include `$kOutputClass.delegate()` in their app\'s');
  b.writeln('/// localizationDelegates, and to list the supported locales.');
  b.writeln('abstract class $kOutputClass {');
  b.writeln('  $kOutputClass(String locale)');
  b.writeln('      : localeName = intl.Intl.canonicalizedLocale(locale);');
  b.writeln();
  b.writeln('  /// The locale this instance serves, canonicalized.');
  b.writeln('  final String localeName;');
  b.writeln();
  b.writeln('  /// Looks up the strings for the current [context].');
  b.writeln('  static $kOutputClass of(BuildContext context) {');
  b.writeln('    return Localizations.of<$kOutputClass>(context, $kOutputClass)!;');
  b.writeln('  }');
  b.writeln();
  b.writeln('  /// The delegate that loads these strings.');
  b.writeln('  static const LocalizationsDelegate<$kOutputClass> delegate =');
  b.writeln('      _${kOutputClass}Delegate();');
  b.writeln();
  b.writeln('  /// The locales this app ships strings for.');
  b.writeln('  static const List<Locale> supportedLocales = <Locale>[');
  for (final String l in locales) {
    b.writeln("    Locale('$l'),");
  }
  b.writeln('  ];');
  b.writeln();
  b.writeln('  /// Whether [locale] is one this app ships strings for.');
  b.writeln('  static bool isSupported(Locale locale) {');
  b.writeln('    return supportedLocales.any(');
  b.writeln('      (Locale supported) =>');
  b.writeln('          intl.Intl.canonicalizedLocale(supported.languageCode) ==');
  b.writeln('          intl.Intl.canonicalizedLocale(locale.languageCode),');
  b.writeln('    );');
  b.writeln('  }');
  b.writeln();
  b.writeln('  /// Resolves a locale to a concrete instance, or null when unsupported.');
  b.writeln('  static Future<$kOutputClass> load(Locale locale) {');
  b.writeln('    return SynchronousFuture<$kOutputClass>(');
  b.writeln('      lookup$kOutputClass(locale),');
  b.writeln('    );');
  b.writeln('  }');
  b.writeln();
  b.writeln('  /// The concrete instance for [locale].');
  b.writeln('  static $kOutputClass lookup$kOutputClass(Locale locale) {');
  b.writeln('    switch (intl.Intl.canonicalizedLocale(locale.toString())) {');
  for (final String l in locales) {
    b.writeln("      case '$l':");
    b.writeln('        return ${kOutputClass}${_pascal(l)}();');
  }
  b.writeln('      default:');
  b.writeln('        return ${kOutputClass}${_pascal(locales.first)}();');
  b.writeln('    }');
  b.writeln('  }');
  b.writeln();
  // The abstract surface every locale subclass implements. gen-l10n emits the
  // same thing (plus `@override`-able doc comments), so the API matches.
  for (final String key in keys) {
    b.writeln('  String get $key;');
    b.writeln();
  }
  b.writeln('}');
  b.writeln();
  b.writeln('class _${kOutputClass}Delegate extends LocalizationsDelegate<$kOutputClass> {');
  b.writeln('  const _${kOutputClass}Delegate();');
  b.writeln();
  b.writeln('  @override');
  b.writeln('  bool isSupported(Locale locale) => $kOutputClass.isSupported(locale);');
  b.writeln();
  b.writeln('  @override');
  b.writeln('  Future<$kOutputClass> load(Locale locale) => $kOutputClass.load(locale);');
  b.writeln();
  b.writeln('  @override');
  b.writeln('  bool shouldReload(_${kOutputClass}Delegate old) => false;');
  b.writeln('}');
  return b.toString();
}

/// `en` -> `En`, `zh` -> `Zh`.
String _pascal(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Emits a Dart string literal for [value].
///
/// Uses a raw string when the value contains backslashes (the ARB files carry
/// `\n` escapes that must reach Dart as literal `\n`, which a raw string gives
/// us for free), and a normal string otherwise so newlines and quotes are
/// escaped properly.
String _dartString(String value) {
  final bool hasBackslash = value.contains(r'\');
  final bool hasNewline = value.contains('\n') || value.contains('\r');

  if (hasBackslash && !hasNewline) {
    // Raw literal: `r'...'`. A single quote in a raw literal cannot be escaped,
    // so fall back when one is present.
    if (!value.contains("'")) {
      return "r'$value'";
    }
    if (!value.contains('"')) {
      return 'r"$value"';
    }
  }
  final String escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\$', r'\$');
  return "'$escaped'";
}
