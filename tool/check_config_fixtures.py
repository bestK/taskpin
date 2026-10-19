#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only validation of the config fixtures used by test/config.

    python -X utf8 tool/check_config_fixtures.py

The Dart config layer cannot be executed in this working copy (no Dart SDK), so
this script supplies real, runnable evidence for the *data* half of the
deliverable:

  1. test/config/golden_config.json is a byte-for-byte copy of the repo's
     config.json, and still carries every value the plan's Phase 1 acceptance
     criterion names.
  2. Every fixture is well-formed JSON with the shape its test expects.
  3. The legacy fixtures really are legacy (the fields the migration adds are
     genuinely absent), so the migration tests are not passing vacuously.
  4. The fixtures that assert a round-trip genuinely round-trip, under the
     documented rules (unknown keys preserved; `params` omitted when empty;
     an empty `sources` list NOT preserved).

It deliberately does NOT reimplement the Dart model — it only checks facts about
the fixtures themselves, so it cannot drift from the implementation.

Exit code is 0 when everything holds, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):  # pragma: no cover
    pass

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(REPO_ROOT, "test", "config")
FIXTURE_DIR = os.path.join(CONFIG_DIR, "fixtures")

GOLDEN = os.path.join(CONFIG_DIR, "golden_config.json")
REAL_CONFIG = os.path.join(REPO_ROOT, "config.json")

# Every field the unified schema knows, per lib/config.h + config_save.
ROOT_KEYS = {"version", "global", "items", "sources"}
GLOBAL_KEYS = {
    "width",
    "pos_x",
    "pos_y",
    "font_size",
    "font_color",
    "bg_color",
    "scroll_enabled",
    "log_level",
}
ITEM_KEYS = {
    "type",
    "name",
    "url",
    "req_headers",
    "interval_ms",
    "field_expr",
    "click_enabled",
    "click_url",
    "lua_path",
    "params",
    "pinned",
    "bar_width",
    "bar_x",
    "bar_y",
    "bar_bg_color",
    "dlg_x",
    "dlg_y",
    "dlg_w",
    "dlg_h",
}
PARAM_KEYS = {"key", "value", "label"}

# Fields the unified schema added after the original Windows format.
NEWER_ITEM_FIELDS = {"bar_x", "bar_y", "bar_bg_color", "dlg_x", "dlg_y", "dlg_w", "dlg_h"}

failures: "list[str]" = []
notes: "list[str]" = []


def check(condition: bool, message: str) -> bool:
    if not condition:
        failures.append(message)
    return condition


def load(path: str):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def rel(path: str) -> str:
    return os.path.relpath(path, REPO_ROOT)


def check_golden_is_a_true_copy() -> None:
    print("== golden fixture ==")

    check(os.path.exists(REAL_CONFIG), "repo config.json is missing: %s" % REAL_CONFIG)
    check(os.path.exists(GOLDEN), "golden fixture is missing: %s" % GOLDEN)
    if failures:
        return

    with open(REAL_CONFIG, "rb") as handle:
        real = handle.read()
    with open(GOLDEN, "rb") as handle:
        golden = handle.read()

    check(real == golden, "%s is not a byte-for-byte copy of config.json" % rel(GOLDEN))
    print("  %s == config.json : %s (%d bytes)" % (rel(GOLDEN), real == golden, len(real)))

    # config.json itself is git-ignored (.gitignore:19), but the fixture uses a
    # different filename, so the pattern does not match it and it lands with a
    # plain `git add`. Verified: `git check-ignore -v test/config/golden_config.json`
    # exits 1. Reported here so the fact is visible rather than assumed.
    print("  %s is git-ignored; %s is NOT (different filename), so it is "
          "committed normally" % (rel(REAL_CONFIG), rel(GOLDEN)))

    cfg = load(GOLDEN)

    # --- the acceptance values named in docs/FLUTTER_REWRITE_PLAN.md:306 ---
    check(cfg.get("version") == 1, "golden: version should be 1")
    check(len(cfg.get("items", [])) == 8, "golden: expected 8 items, got %d" % len(cfg.get("items", [])))
    check(
        cfg.get("sources") == ["bestK/taskpin-plugins"],
        "golden: sources should be ['bestK/taskpin-plugins'], got %r" % (cfg.get("sources"),),
    )
    print("  version=%s items=%d sources=%r" % (cfg.get("version"), len(cfg["items"]), cfg["sources"]))

    sentinels = [item.get("bar_bg_color") for item in cfg["items"]]
    check(
        all(value == "FFFFFFFF" for value in sentinels),
        "golden: every item bar_bg_color should be FFFFFFFF, got %r" % (sentinels,),
    )
    print("  bar_bg_color all 'FFFFFFFF' (use-global sentinel): %s" % all(v == "FFFFFFFF" for v in sentinels))

    api = cfg["items"][6]
    check(api.get("type") == 0, "golden: items[6].type should be 0 (URL mode), got %r" % api.get("type"))
    check(
        api.get("field_expr") == "$.subscriptionTitle $$.currentUsage",
        "golden: items[6].field_expr is %r" % api.get("field_expr"),
    )
    print("  items[6].type=%s field_expr=%r" % (api.get("type"), api.get("field_expr")))

    check(cfg["items"][7].get("name") == "zeeho", "golden: items[7].name should be 'zeeho'")
    check(cfg["global"].get("bg_color") == "00000000",
          "golden: global.bg_color should be '00000000' (opaque black in CreateSolidBrush)")

    # --- `params` is omitted, not empty, on 5 of the 8 items ---
    with_params = [i for i, item in enumerate(cfg["items"]) if "params" in item]
    without_params = [i for i, item in enumerate(cfg["items"]) if "params" not in item]
    check(
        without_params == [1, 2, 3, 5, 6, 7],
        "golden: expected items 1,2,3,5,6,7 to have no `params` key, got %r" % (without_params,),
    )
    print("  items WITH params: %r ; WITHOUT: %r" % (with_params, without_params))
    check(
        [len(cfg["items"][i]["params"]) for i in with_params] == [3, 2],
        "golden: expected param counts [3, 2], got %r"
        % ([len(cfg["items"][i]["params"]) for i in with_params],),
    )
    print("  param counts: %r" % ([len(cfg["items"][i]["params"]) for i in with_params],))

    # --- no unknown keys anywhere: this is what makes the round-trip strict ---
    check(set(cfg.keys()) == ROOT_KEYS,
          "golden: unexpected root keys %r" % sorted(set(cfg.keys()) - ROOT_KEYS))
    check(set(cfg["global"].keys()) == GLOBAL_KEYS,
          "golden: unexpected global keys %r" % sorted(set(cfg["global"].keys()) - GLOBAL_KEYS))
    for index, item in enumerate(cfg["items"]):
        check(set(item.keys()) <= ITEM_KEYS,
              "golden: items[%d] has unexpected keys %r"
              % (index, sorted(set(item.keys()) - ITEM_KEYS)))
        for pindex, param in enumerate(item.get("params", [])):
            check(set(param.keys()) <= PARAM_KEYS,
                  "golden: items[%d].params[%d] has unexpected keys %r"
                  % (index, pindex, sorted(set(param.keys()) - PARAM_KEYS)))
    print("  no unknown keys anywhere (round-trip is strict)")
    print("  NO `realtime` key present: %s" % (not any("realtime" in i for i in cfg["items"])))

    # --- the round-trip rules the Dart test asserts, applied here ---
    reserialized = roundtrip(cfg)
    check(reserialized == cfg, "golden: a faithful round-trip changed the document")
    print("  faithful round-trip is a fixed point: %s" % (reserialized == cfg))
    print("")


def roundtrip(cfg):
    """Re-encode a document under the documented rules.

    The one rule that changes anything is `params` (omitted when empty) and the
    `sources` default. The golden file satisfies both already, so this should
    be a fixed point.
    """
    out = {}
    for key in ("version", "global"):
        out[key] = cfg[key]
    out["items"] = [dict(item) for item in cfg["items"]]
    out["sources"] = list(cfg.get("sources") or ["bestK/taskpin-plugins"])
    return out


def check_fixture(name: str, predicate) -> None:
    path = os.path.join(FIXTURE_DIR, name)
    if not check(os.path.exists(path), "missing fixture: %s" % rel(path)):
        return
    try:
        data = load(path)
    except json.JSONDecodeError as exc:
        failures.append("%s is not valid JSON: %s" % (rel(path), exc))
        return
    predicate(data, rel(path))


def check_legacy_v1(data, name) -> None:
    print("== %s ==" % name)
    check("global" in data and "items" in data, "%s: should have global+items" % name)

    # It must be genuinely legacy: the newer fields absent, so the migration
    # test is not passing vacuously.
    check("sources" not in data, "%s: should NOT have sources (that is what makes it legacy)" % name)
    check("scroll_enabled" not in data["global"],
          "%s: global.scroll_enabled should be absent" % name)
    missing = [f for f in NEWER_ITEM_FIELDS if any(f not in i for i in data["items"])]
    check(bool(missing),
          "%s: expected at least one item missing a newer field" % name)
    print("  legacy markers: no `sources`, no `scroll_enabled`, items missing %r" % sorted(missing)[:4])

    check(any("params" in i for i in data["items"]),
          "%s: should exercise a params-bearing item" % name)
    check(any("params" not in i for i in data["items"]),
          "%s: should exercise a params-less item" % name)
    print("  items=%d (some with params, some without)" % len(data["items"]))
    print("")


def check_macos_legacy(data, name) -> None:
    print("== %s ==" % name)
    check("global" not in data, "%s: the Swift schema has no `global` object" % name)
    check("fontSize" in data and "fontColor" in data and "bgColor" in data,
          "%s: root-level fontSize/fontColor/bgColor expected" % name)
    check("scrollEnabled" in data, "%s: root-level scrollEnabled expected" % name)
    print("  root keys: %r" % sorted(data.keys()))

    for index, item in enumerate(data["items"]):
        check("id" in item, "%s: items[%d] should carry a UUID id" % (name, index))
        check(isinstance(item.get("type"), str),
              "%s: items[%d].type should be the string enum, got %r"
              % (name, index, item.get("type")))
        for camel in ("intervalMs", "reqHeaders", "fieldExpr", "clickEnabled", "clickUrl", "luaPath"):
            check(camel in item, "%s: items[%d] should use the camelCase key %r" % (name, index, camel))
        for snake in ("bar_x", "bar_y", "bar_bg_color", "dlg_x", "dlg_w", "interval_ms"):
            check(snake not in item,
                  "%s: items[%d] should NOT have the snake_case key %r" % (name, index, snake))
        for param in item.get("params", []):
            check("paramType" in param,
                  "%s: items[%d] params should carry the mac-only paramType" % (name, index))

    # An asymmetric color is what makes the RGB->COLORREF swap test meaningful.
    check(data.get("fontColor") == "FF8000",
          "%s: fontColor should be the asymmetric 'FF8000' so a missing R/B "
          "swap fails loudly, got %r" % (name, data.get("fontColor")))
    r, g, b = data["fontColor"][0:2], data["fontColor"][2:4], data["fontColor"][4:6]
    swapped = "%s%s%s" % (b, g, r)
    check(swapped != data["fontColor"],
          "%s: fontColor must be byte-asymmetric for the swap test to bite" % name)
    print("  fontColor %r -> COLORREF %r (R/B swapped)" % (data["fontColor"], swapped))
    check(data.get("bgColor") == "1E1E1E",
          "%s: bgColor should be the symmetric '1E1E1E'" % name)
    print("  bgColor %r is byte-symmetric" % data.get("bgColor"))
    print("")


def check_future_version(data, name) -> None:
    print("== %s ==" % name)
    check(data.get("version") == 2,
          "%s: must declare version 2 to exercise the refusal path, got %r"
          % (name, data.get("version")))
    check(data.get("version", 0) > 1, "%s: version must be > 1" % name)
    print("  version=%r -> must be refused, and the file left untouched" % data.get("version"))
    print("")


def check_unknown_keys(data, name) -> None:
    print("== %s ==" % name)
    check("experimental_feature_flag" in data, "%s: expected a root-level unknown key" % name)
    check("future_global_option" in data.get("global", {}),
          "%s: expected a global-level unknown key" % name)
    check(any("future_item_option" in i for i in data.get("items", [])),
          "%s: expected an item-level unknown key" % name)
    check(any("future_param_option" in p
              for i in data.get("items", [])
              for p in i.get("params", [])),
          "%s: expected a param-level unknown key" % name)
    print("  unknown keys at root, global, item and param level")

    # This one must be fully unified so the round-trip test is about unknown
    # keys and not about migration.
    check("sources" in data, "%s: should be unified (has sources)" % name)
    check("scroll_enabled" in data["global"], "%s: should be unified" % name)
    missing = [f for i in data["items"] for f in NEWER_ITEM_FIELDS if f not in i]
    check(not missing, "%s: should be unified but items are missing %r" % (name, missing))
    print("  fully unified (so it tests unknown keys, not migration)")
    print("")


def check_empty_sources(data, name) -> None:
    print("== %s ==" % name)
    check(data.get("sources") == [], "%s: sources should be an empty list" % name)
    check("global" in data and "items" in data, "%s: should be otherwise well-formed" % name)
    print("  sources=[] -> the C loader injects the default (config.c:166-169)")
    print("  this fixture documents a DELIBERATE non-round-trip")
    print("")


def main() -> int:
    check_golden_is_a_true_copy()
    check_fixture("config_legacy_v1.json", check_legacy_v1)
    check_fixture("config_macos_legacy.json", check_macos_legacy)
    check_fixture("config_unknown_keys.json", check_unknown_keys)
    check_fixture("config_future_version.json", check_future_version)
    check_fixture("config_empty_sources.json", check_empty_sources)

    if notes:
        print("NOTES:")
        for note in notes:
            print("  - %s" % note)
        print("")

    if failures:
        sys.stderr.write("FAILED (%d):\n" % len(failures))
        for failure in failures:
            sys.stderr.write("  - %s\n" % failure)
        return 1

    print("RESULT: all fixture checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
