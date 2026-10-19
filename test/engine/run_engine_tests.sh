#!/usr/bin/env bash
# test/engine/run_engine_tests.sh — regression harness for native/engine.
#
# Run after building the engine CLI:
#
#   cmake -S native/engine -B native/engine/build -G Ninja \
#         -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=/d/mingw64/bin/gcc.exe
#   cmake --build native/engine/build
#   bash test/engine/run_engine_tests.sh
#
# Exits non-zero on the first failure. Uses python3 only for JSON parsing.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${REPO_ROOT}/native/engine/build/engine_cli.exe"
TMP="${REPO_ROOT}/native/engine/build/tmp"
[ -x "$CLI" ] || CLI="${REPO_ROOT}/native/engine/build/engine_cli"

PASS=0
FAIL=0

check() { # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $1"
        echo "        expected: $2"
        echo "        actual:   $3"
        FAIL=$((FAIL + 1))
    fi
}

field() { # field <json> <python-expr on d>
    printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null
}

re_ok() { # re_ok <json> <python-expr on d, evaluating to a string> <regex>
    printf '%s' "$1" | python3 -c "
import sys,json,re
d=json.load(sys.stdin)
print('yes' if re.match(sys.argv[1], str($2)) else 'no')
" "$3" 2>/dev/null
}

mkdir -p "$TMP"

if [ ! -x "$CLI" ]; then
    echo "engine_cli not found at $CLI — build it first (see header)."
    exit 2
fi

echo "=== 1. font() arity regression ==="
# The macOS bridge guarded with lua_gettop(L) >= 3, so font("a", "#fff")
# silently dropped the colour. lib/scripting.c gets this right and the port
# must too.
cat > "$TMP/font_arity.lua" <<'LUA'
return font("one")
    .. font("two", "#FF0000")
    .. font("three", "#00FF00", 14)
    .. font("four", "#0000FF", 16, "right")
LUA
OUT="$("$CLI" "$TMP/font_arity.lua" 2>/dev/null)"
check "2-arg font keeps its colour" "#FF0000" "$(field "$OUT" "d['spans'][1]['color']")"
check "1-arg font has no colour"    ""        "$(field "$OUT" "d['spans'][0]['color']")"
check "3-arg font colour"           "#00FF00" "$(field "$OUT" "d['spans'][2]['color']")"
check "3-arg font size"             "14"      "$(field "$OUT" "d['spans'][2]['font_size']")"
check "4-arg font align"            "1"       "$(field "$OUT" "d['spans'][3]['align']")"

echo "=== 2. align / newline present and correct ==="
OUT="$("$CLI" "$REPO_ROOT/examples/rich_text_demo.lua" 2>/dev/null)"
check "span_count"        "7"          "$(field "$OUT" "d['span_count']")"
check "align[]"           "[0, 0, 1, 0, 0, 0, 1]" "$(field "$OUT" "[s['align'] for s in d['spans']]")"
check "newline[]"         "[0, 0, 0, 1, 0, 0, 0]" "$(field "$OUT" "[s['newline'] for s in d['spans']]")"

echo "=== 3. tuple parsing (display, clickable, dialog) ==="
OUT="$("$CLI" "$REPO_ROOT/examples/hud_clock.lua" 2>/dev/null)"
check "clickable"          "1"    "$(field "$OUT" "d['clickable']")"
check "click_action=DIALOG" "1"   "$(field "$OUT" "d['click_action']")"
check "dialog.borderless"  "1"    "$(field "$OUT" "d['dialog']['borderless']")"
check "dialog.clickthrough" "1"   "$(field "$OUT" "d['dialog']['clickthrough']")"
check "dialog.opacity"     "180"  "$(field "$OUT" "d['dialog']['opacity']")"
check "dialog.item_count"  "2"    "$(field "$OUT" "d['dialog']['item_count']")"

echo "=== 4. @param / @refresh parsing ==="
OUT="$("$CLI" "$REPO_ROOT/scripts/zeeho.lua" 2>/dev/null)"
check "refresh_ms"         "30000"    "$(field "$OUT" "d['refresh_ms']")"
check "param count"        "1"        "$(field "$OUT" "len(d['params'])")"
check "param key"          "VIN"      "$(field "$OUT" "d['params'][0]['key']")"
check "param type"         "string"   "$(field "$OUT" "d['params'][0]['type']")"

echo "=== 5. watchdog (while true do end must abort, not hang) ==="
printf 'local i = 0\nwhile true do i = i + 1 end\n' > "$TMP/infinite.lua"
START=$(date +%s%N)
OUT="$(timeout 20 "$CLI" "$TMP/infinite.lua" 2>/dev/null)"
RC=$?
ELAPSED_MS=$(( ($(date +%s%N) - START) / 1000000 ))
# engine_cli exits 1 when the script fails; 124 would mean it was killed by
# timeout, i.e. the watchdog did not fire.
check "exited on its own (0/1, not 124)" "1" "$RC"
check "ok == 0"                         "0" "$(field "$OUT" "d['ok']")"
case "$(field "$OUT" "d['error']")" in
    *"instruction budget exceeded"*) check "error mentions the watchdog" "yes" "yes" ;;
    *)                               check "error mentions the watchdog" "yes" "no" ;;
esac
if [ "$ELAPSED_MS" -lt 2000 ]; then
    check "aborted in < 2000 ms (took ${ELAPSED_MS} ms)" "yes" "yes"
else
    check "aborted in < 2000 ms (took ${ELAPSED_MS} ms)" "yes" "no"
fi

echo "=== 6. every example/script produces parseable JSON ==="
for f in "$REPO_ROOT"/examples/*.lua "$REPO_ROOT"/scripts/*.lua; do
    OUT="$(timeout 30 "$CLI" "$f" 2>/dev/null)"
    if [ -z "$OUT" ]; then
        check "no crash: $(basename "$f")" "runs" "crashed/timed out"
    elif [ -z "$(field "$OUT" "'ok'")" ]; then
        check "valid JSON: $(basename "$f")" "valid" "invalid"
    else
        PASS=$((PASS + 1))
    fi
done
echo "  (all scripts emitted JSON)"

echo "=== 7. sys.country() / sys.language() — OS locale, instant, no network ==="
# These read the OS regional settings (GetUserDefaultGeoName /
# GetUserDefaultLocaleName), NOT the network. Shape is asserted rather than a
# fixed value, because the correct answer depends on how this machine is set
# up: country is ISO 3166-1 alpha-2, language is a BCP-47-ish locale name.
cat > "$TMP/locale.lua" <<'LUA'
return sys.country() .. "|" .. sys.language()
LUA
OUT="$(timeout 10 "$CLI" "$TMP/locale.lua" 2>/dev/null)"
COUNTRY="$(field "$OUT" "d['display'].split('|')[0]")"
LANGUAGE="$(field "$OUT" "d['display'].split('|')[1]")"
check "country() is a string"    "str" "$(field "$OUT" "type(d['display']).__name__")"
check "country() is 2 uppercase letters (got '$COUNTRY')" \
      "yes" "$(re_ok "$OUT" "d['display'].split('|')[0]" '^[A-Z]{2}$')"
check "language() matches a locale name (got '$LANGUAGE')" \
      "yes" "$(re_ok "$OUT" "d['display'].split('|')[1]" '^[A-Za-z]{2,3}(-[A-Za-z0-9]+)*$')"
check "country() and language() are non-empty on this box" "yes" \
      "$([ -n "$COUNTRY" ] && [ -n "$LANGUAGE" ] && echo yes || echo no)"

echo "=== 8. sys.is_china() — network geo-IP, cached, boolean ==="
cat > "$TMP/china.lua" <<'LUA'
local a = sys.is_china()
local b = sys.is_china()
return tostring(a) .. "|" .. tostring(b) .. "|" .. type(a)
LUA
OUT="$(timeout 30 "$CLI" "$TMP/china.lua" 2>/dev/null)"
check "is_china() returns a boolean" "boolean" "$(field "$OUT" "d['display'].split('|')[2]")"
# The cache means two calls in one run must agree; and because the result is
# cached process-wide, a second run must also agree with the first.
check "is_china() is stable within a run" "yes" \
      "$([ "$(field "$OUT" "d['display'].split('|')[0]")" = "$(field "$OUT" "d['display'].split('|')[1]")" ] && echo yes || echo no)"
OUT2="$(timeout 30 "$CLI" "$TMP/china.lua" 2>/dev/null)"
check "is_china() is stable across runs (cached)" \
      "$(field "$OUT" "d['display'].split('|')[0]")" \
      "$(field "$OUT2" "d['display'].split('|')[0]")"

echo "=== 9. sys.is_china() offline — dead endpoint returns false, no crash/hang ==="
# Point the endpoint at a closed port. This is the offline case: the call must
# resolve to false and must not hang past the HTTP timeout.
START=$(date +%s%N)
OUT="$(TASKPIN_GEO_URL=http://127.0.0.1:9/geoip timeout 30 "$CLI" "$TMP/china.lua" 2>/dev/null)"
RC=$?
OFFLINE_MS=$(( ($(date +%s%N) - START) / 1000000 ))
# engine_cli exits 0 when the script ran (ok=1) and 1 when it raised; 124 would
# mean the timeout killed it. The offline path is a clean success, so 0.
check "offline run exits cleanly (0, not 1/124)" "0" "$RC"
check "offline is_china() is false" "false" "$(field "$OUT" "d['display'].split('|')[0]")"
check "offline is_china() is a boolean" "boolean" "$(field "$OUT" "d['display'].split('|')[2]")"
if [ "$OFFLINE_MS" -lt 30000 ]; then
    check "offline call did not hang (took ${OFFLINE_MS} ms)" "yes" "yes"
else
    check "offline call did not hang (took ${OFFLINE_MS} ms)" "yes" "no"
fi

echo "=== 10. sys.gh_proxy() — composes with is_china(), idempotent ==="
cat > "$TMP/ghproxy.lua" <<'LUA'
local cn = sys.is_china()
return tostring(cn) .. "|"
    .. sys.gh_proxy("https://github.com/bestK/taskpin") .. "|"
    .. sys.gh_proxy("https://raw.githubusercontent.com/bestK/x/master/a.png") .. "|"
    .. sys.gh_proxy("https://example.com/foo") .. "|"
    .. sys.gh_proxy("https://gh-proxy.com/https://github.com/a/b")
LUA
OUT="$(timeout 30 "$CLI" "$TMP/ghproxy.lua" 2>/dev/null)"
CN="$(field "$OUT" "d['display'].split('|')[0]")"
GH="$(field "$OUT" "d['display'].split('|')[1]")"
RAW="$(field "$OUT" "d['display'].split('|')[2]")"
OTHER="$(field "$OUT" "d['display'].split('|')[3]")"
IDEM="$(field "$OUT" "d['display'].split('|')[4]")"

# Non-GitHub hosts are never rewritten, whichever branch we are on: gh-proxy
# can only fetch from GitHub, so prefixing anything else yields a dead URL.
check "non-GitHub host passes through unchanged" "https://example.com/foo" "$OTHER"
check "already-proxied URL is not double-wrapped" \
      "https://gh-proxy.com/https://github.com/a/b" "$IDEM"

if [ "$CN" = "true" ]; then
    check "in CN: github.com is mirrored" \
          "https://gh-proxy.com/https://github.com/bestK/taskpin" "$GH"
    check "in CN: raw.githubusercontent.com is mirrored" \
          "https://gh-proxy.com/https://raw.githubusercontent.com/bestK/x/master/a.png" "$RAW"
else
    check "not in CN: github.com is untouched" "https://github.com/bestK/taskpin" "$GH"
    check "not in CN: raw.githubusercontent.com is untouched" \
          "https://raw.githubusercontent.com/bestK/x/master/a.png" "$RAW"
fi

# The offline path must also leave URLs alone (is_china() false => no proxy).
OUT="$(TASKPIN_GEO_URL=http://127.0.0.1:9/geoip timeout 30 "$CLI" "$TMP/ghproxy.lua" 2>/dev/null)"
check "offline: gh_proxy leaves GitHub URLs alone" \
      "https://github.com/bestK/taskpin" "$(field "$OUT" "d['display'].split('|')[1]")"

echo "=== 11. sys.watch_keys() / key_pressed() / key_triggered() ==="
# scripts/dino_runner.lua is the only caller. It calls
# watch_keys("space","up","lclick"), then key_triggered(...) with
# key_pressed(...) as a fallback. All three must exist with those shapes.
# Real keypresses cannot be exercised headlessly, so this pins the contract
# (presence, arity, return types) rather than the live key state.
cat > "$TMP/keys.lua" <<'LUA'
local w = sys.watch_keys("space", "up", "lclick")
return table.concat(w, ",") .. "|"
    .. #sys.watch_keys() .. "|"
    .. type(sys.key_pressed) .. "|"
    .. type(sys.key_triggered) .. "|"
    .. type(sys.key_pressed("space")) .. "|"
    .. type(sys.key_triggered("space")) .. "|"
    .. tostring(sys.key_pressed("no-such-key")) .. "|"
    .. tostring(sys.key_triggered("no-such-key"))
LUA
OUT="$(timeout 10 "$CLI" "$TMP/keys.lua" 2>/dev/null)"
check "watch_keys() resolves the dino_runner keys" "space,up,lclick" "$(field "$OUT" "d['display'].split('|')[0]")"
check "watch_keys() with no args is empty" "0" "$(field "$OUT" "d['display'].split('|')[1]")"
check "key_pressed is a function"   "function" "$(field "$OUT" "d['display'].split('|')[2]")"
check "key_triggered is a function" "function" "$(field "$OUT" "d['display'].split('|')[3]")"
check "key_pressed() returns a boolean"   "boolean" "$(field "$OUT" "d['display'].split('|')[4]")"
check "key_triggered() returns a boolean" "boolean" "$(field "$OUT" "d['display'].split('|')[5]")"
check "unknown key -> key_pressed false"   "false" "$(field "$OUT" "d['display'].split('|')[6]")"
check "unknown key -> key_triggered false" "false" "$(field "$OUT" "d['display'].split('|')[7]")"

echo "=== 12. dino_runner.lua and webview_demo.lua now run (ok:1) ==="
OUT="$(timeout 30 "$CLI" "$REPO_ROOT/scripts/dino_runner.lua" 2>/dev/null)"
check "dino_runner ok"        "1" "$(field "$OUT" "d['ok']")"
check "dino_runner error"     ""  "$(field "$OUT" "d['error']")"
check "dino_runner has spans" "yes" \
      "$(field "$OUT" "'yes' if d['span_count'] > 0 else 'no'")"

OUT="$(timeout 30 "$CLI" "$REPO_ROOT/scripts/webview_demo.lua" 2>/dev/null)"
check "webview_demo ok"            "1" "$(field "$OUT" "d['ok']")"
check "webview_demo error"         ""  "$(field "$OUT" "d['error']")"
check "transparent_bg carried"     "1" "$(field "$OUT" "d['dialog']['transparent_bg']")"
check "webview item type"          "webview" "$(field "$OUT" "d['dialog']['items'][0]['type']")"
check "webview width carried"      "580" "$(field "$OUT" "d['dialog']['items'][0]['web_w']")"
check "webview height carried"     "460" "$(field "$OUT" "d['dialog']['items'][0]['web_h']")"
check "webview url carried" "yes" \
      "$(re_ok "$OUT" "d['dialog']['items'][0]['url']" '^https://.*webview_demo\.html$')"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1