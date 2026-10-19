// `req_headers` <-> header-list conversion.
//
// `PinItem.req_headers` is a single raw STRING, not a list:
//
//   "x-api-key:sk-...\r\n"
//
// The engine's contract is explicit about the separator — `native/engine/tp_http.h`
// says "headers  UTF-8 extra headers, CRLF separated, or NULL", and
// `tp_http_win.c:115` hands the string straight to WinHTTP after appending CRLF
// if it is missing (`lib/fetcher.c:56-61` does the same on the old path).
//
// So the on-disk format is CRLF-delimited and must stay that way: a
// LF-only rewrite would be a silent format change, and `\r\n` inside a JSON
// string is written as the two-character escape `\r\n`, which round-trips
// exactly.
//
// The editor wants name/value PAIRS (`TpHeaderListEditor` takes
// `TpHeaderEntry`s), so this file owns both directions and is the only place
// that knows about the separator.
//
// Pure Dart — analysable and testable without the Flutter SDK.

/// The line separator used on disk. `\r\n`, matching WinHTTP.
const String kHeaderSeparator = '\r\n';

/// A header as name + value.
class HeaderPair {
  const HeaderPair({required this.name, required this.value});

  final String name;
  final String value;

  bool get isEmpty => name.trim().isEmpty && value.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is HeaderPair && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => '$name: $value';
}

/// Splits a raw `req_headers` string into pairs.
///
/// Tolerant by design, because the field has been hand-editable in the old
/// ImGui/Win32 dialogs for years and real configs contain whatever people typed:
///
///   * CRLF, LF and CR all split (the writer always emits CRLF; the reader
///     accepts what is there rather than mis-parsing a file edited elsewhere).
///   * Blank lines are dropped.
///   * A line with no `:` becomes a name with an empty value, rather than being
///     discarded — losing a line the user typed is worse than showing it oddly.
///   * Only the FIRST `:` splits, so `Authorization: Bearer a:b` keeps its
///     value intact (a URL or a JWT would otherwise be mangled).
///   * Names are trimmed; values keep their inner spacing but lose the single
///     conventional space after the colon.
List<HeaderPair> decodeHeaders(String raw) {
  if (raw.trim().isEmpty) return const <HeaderPair>[];

  final List<HeaderPair> out = <HeaderPair>[];
  for (final String line in raw.split(RegExp(r'\r\n|\n|\r'))) {
    if (line.trim().isEmpty) continue;
    final int colon = line.indexOf(':');
    if (colon < 0) {
      out.add(HeaderPair(name: line.trim(), value: ''));
      continue;
    }
    final String name = line.substring(0, colon).trim();
    String value = line.substring(colon + 1);
    // Drop exactly one leading space — the conventional `Name: value` form.
    if (value.startsWith(' ')) value = value.substring(1);
    out.add(HeaderPair(name: name, value: value));
  }
  return out;
}

/// Joins pairs back into the raw CRLF-delimited form.
///
/// Blank rows are skipped so an empty editor row does not become a bare CRLF,
/// and a trailing CRLF is ALWAYS emitted — `lib/fetcher.c:56-61` appends one if
/// missing, and the C writer stores the string as-is, so emitting it here keeps
/// the file stable across a round-trip instead of growing a `\r\n` on the next
/// C-side save.
String encodeHeaders(List<HeaderPair> pairs) {
  final StringBuffer buffer = StringBuffer();
  for (final HeaderPair p in pairs) {
    if (p.isEmpty) continue;
    buffer.write(p.name.trim());
    buffer.write(':');
    if (p.value.isNotEmpty) {
      buffer.write(' ');
      buffer.write(p.value);
    }
    buffer.write(kHeaderSeparator);
  }
  return buffer.toString();
}

/// True when the raw string carries no usable header.
bool headersAreEmpty(String raw) => decodeHeaders(raw).isEmpty;
