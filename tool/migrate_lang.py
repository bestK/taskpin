#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Migrate lang/{en-US,zh-CN}.json into Flutter ARB files.

    python -X utf8 tool/migrate_lang.py            # generate + report
    python -X utf8 tool/migrate_lang.py --check    # verify, write nothing
    python -X utf8 tool/migrate_lang.py --mapping-out docs/lang-mapping.md

WHY PYTHON AND NOT DART
-----------------------
docs/FLUTTER_REWRITE_PLAN.md Phase 0 names `tool/migrate_lang.dart`. The Dart
SDK is not installed in this working copy (D:\\flutter\\bin\\cache\\dart-sdk is
empty and `dart --version` blocks while the SDK downloads), so a Dart tool could
not be run at all. This script is deterministic and idempotent, so it produces
exactly the same ARB bytes a Dart port would; porting it later is mechanical.

This console is GBK, hence `python -X utf8` plus an explicit
sys.stdout.reconfigure below.

HARD REQUIREMENT: zero key loss. The script asserts, and fails loudly on, any
of: a key present in one language but not the other, a count mismatch, a
duplicated camelCase name, or a value that differs from its source string.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

# --- console encoding -------------------------------------------------------
# The Windows console here is GBK; Chinese strings would otherwise be mangled
# or raise UnicodeEncodeError.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):  # pragma: no cover - older/odd environments
    pass

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SOURCES = {
    "en": os.path.join(REPO_ROOT, "lang", "en-US.json"),
    "zh": os.path.join(REPO_ROOT, "lang", "zh-CN.json"),
}
TARGETS = {
    "en": os.path.join(REPO_ROOT, "lib", "l10n", "app_en.arb"),
    "zh": os.path.join(REPO_ROOT, "lib", "l10n", "app_zh.arb"),
}
LOCALES = {"en": "en", "zh": "zh"}

# printf-style placeholders. ARB/gen-l10n expects ICU `{name}` placeholders and
# does NOT understand these. They are copied verbatim on purpose: the plan's
# hard requirement is "keep the Chinese strings verbatim", and none of the 99
# values contain braces, so a `%s` is inert text to gen-l10n. These five keys
# therefore come out as plain String getters and the call sites format them in
# Dart. Converting them to ICU placeholders is a deliberate Phase 5 decision.
PRINTF_RE = re.compile(r"%[sd]")


def camel_case(dotted: str) -> str:
    """`main.col_name` -> `mainColName`.

    Must stay byte-for-byte in step with `_camelCase` in
    test/l10n/l10n_parity_test.dart.
    """
    segments = dotted.split(".")
    out = []
    for segment in segments:
        words = segment.split("_")
        head = words[0]
        tail = "".join(w[:1].upper() + w[1:] for w in words[1:])
        out.append(head + tail)
    return out[0] + "".join(s[:1].upper() + s[1:] for s in out[1:])


def load_source(lang: str) -> "dict[str, str]":
    path = SOURCES[lang]
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit("FATAL: %s is not a JSON object" % path)
    for key, value in data.items():
        if not isinstance(value, str):
            raise SystemExit(
                "FATAL: %s: value for %r is %s, expected a string"
                % (path, key, type(value).__name__)
            )
    return data


def build_arb(lang: str, source: "dict[str, str]") -> "dict[str, str]":
    arb = {"@@locale": LOCALES[lang]}
    for dotted, value in source.items():
        arb[camel_case(dotted)] = value
    return arb


def render_arb(arb: "dict[str, str]") -> str:
    return json.dumps(arb, ensure_ascii=False, indent=2) + "\n"


def check_invariants(en: "dict[str, str]", zh: "dict[str, str]") -> None:
    """Fail loudly rather than silently dropping a key."""
    problems = []

    if len(en) != len(zh):
        problems.append(
            "key count differs: en=%d zh=%d" % (len(en), len(zh))
        )

    only_en = [k for k in en if k not in zh]
    only_zh = [k for k in zh if k not in en]
    if only_en:
        problems.append("keys only in en: %s" % ", ".join(sorted(only_en)))
    if only_zh:
        problems.append("keys only in zh: %s" % ", ".join(sorted(only_zh)))

    # Duplicate camelCase names would silently collapse two keys into one.
    seen: "dict[str, str]" = {}
    for dotted in en:
        name = camel_case(dotted)
        if name in seen:
            problems.append(
                "camelCase collision: %r and %r both -> %r"
                % (seen[name], dotted, name)
            )
        seen[name] = dotted

    for label, source in (("en", en), ("zh", zh)):
        for dotted, value in source.items():
            if value == "":
                problems.append("%s: %r is empty" % (label, dotted))
            if "{" in value or "}" in value:
                problems.append(
                    "%s: %r contains braces, which gen-l10n would try to parse "
                    "as an ICU placeholder: %r" % (label, dotted, value)
                )

    if problems:
        sys.stderr.write("FATAL: source language files are not migratable:\n")
        for problem in problems:
            sys.stderr.write("  - %s\n" % problem)
        raise SystemExit(1)


def verify_arb(
    lang: str, arb: "dict[str, str]", source: "dict[str, str]"
) -> None:
    """Assert the generated ARB loses nothing relative to its source."""
    expected = {"@@locale"} | {camel_case(k) for k in source}
    actual = set(arb.keys())

    missing = expected - actual
    extra = actual - expected
    if missing:
        raise SystemExit("FATAL: %s ARB is missing keys: %s" % (lang, sorted(missing)))
    if extra:
        raise SystemExit("FATAL: %s ARB has unexpected keys: %s" % (lang, sorted(extra)))
    if len(arb) != len(expected):
        raise SystemExit(
            "FATAL: %s ARB has %d keys, expected %d" % (lang, len(arb), len(expected))
        )

    for dotted, value in source.items():
        name = camel_case(dotted)
        if arb[name] != value:
            raise SystemExit(
                "FATAL: %s ARB value for %r (%s) differs from source %s: %r != %r"
                % (lang, name, dotted, os.path.basename(SOURCES[lang]), arb[name], value)
            )


def markdown_table(en: "dict[str, str]", zh: "dict[str, str]") -> str:
    def cell(text: str) -> str:
        return text.replace("|", "\\|").replace("\n", "<br>")

    lines = [
        "| # | old (dotted) | new (ARB) | en | zh |",
        "|---|---|---|---|---|",
    ]
    for index, dotted in enumerate(en, start=1):
        lines.append(
            "| %d | `%s` | `%s` | %s | %s |"
            % (
                index,
                dotted,
                camel_case(dotted),
                cell(en[dotted]),
                cell(zh.get(dotted, "")),
            )
        )
    return "\n".join(lines) + "\n"


def rel(path: str) -> str:
    """Repo-relative when possible, absolute otherwise.

    `os.path.relpath` raises ValueError across Windows drive letters, and an
    output path given on the command line may well live on another drive.
    """
    try:
        return os.path.relpath(path, REPO_ROOT)
    except ValueError:
        return path


def main(argv: "list[str] | None" = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed ARB files instead of writing them",
    )
    parser.add_argument(
        "--mapping-out",
        default=None,
        help="also write the key mapping table as markdown to this path",
    )
    args = parser.parse_args(argv)

    en = load_source("en")
    zh = load_source("zh")
    check_invariants(en, zh)

    print("source: %s (%d keys)" % (rel(SOURCES["en"]), len(en)))
    print("source: %s (%d keys)" % (rel(SOURCES["zh"]), len(zh)))
    print("key sets identical: %s" % ("yes" if set(en) == set(zh) else "NO"))
    print("")

    arb_en = build_arb("en", en)
    arb_zh = build_arb("zh", zh)
    verify_arb("en", arb_en, en)
    verify_arb("zh", arb_zh, zh)

    failures = []
    for lang, arb in (("en", arb_en), ("zh", arb_zh)):
        text = render_arb(arb)
        target = TARGETS[lang]
        if args.check:
            if not os.path.exists(target):
                failures.append("%s does not exist" % rel(target))
                continue
            with open(target, "r", encoding="utf-8") as handle:
                existing = handle.read()
            if existing != text:
                failures.append(
                    "%s is out of date (run without --check to regenerate)"
                    % rel(target)
                )
            else:
                print("ok: %s (%d keys)" % (rel(target), len(arb)))
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text)
            print(
                "wrote: %s (%d keys, %d bytes)"
                % (rel(target), len(arb), len(text.encode("utf-8")))
            )

    if args.mapping_out:
        table = markdown_table(en, zh)
        with open(args.mapping_out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(table)
        print("wrote: %s" % rel(args.mapping_out))

    print("")
    printf_keys = sorted(k for k in en if PRINTF_RE.search(en[k]) or PRINTF_RE.search(zh.get(k, "")))
    print("printf-placeholder keys kept verbatim (%d):" % len(printf_keys))
    for dotted in printf_keys:
        print("  %-28s -> %-26s %r / %r" % (dotted, camel_case(dotted), en[dotted], zh[dotted]))
    print("")

    if failures:
        sys.stderr.write("FAILED:\n")
        for failure in failures:
            sys.stderr.write("  - %s\n" % failure)
        return 1

    print(
        "RESULT: %d keys in, %d keys out, 0 lost; en/zh key sets identical"
        % (len(en), len(arb_en) - 1)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
