#!/bin/sh
# End-to-end runtime checks: builds libms_rt.a and drives it from a C harness.
# Usage: crates/ms-rt/tests/e2e/run.sh   (CARGO_TARGET_DIR respected)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/target}
(cd "$root" && cargo build -q -p ms-rt)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc -O1 -g -fno-omit-frame-pointer -fno-optimize-sibling-calls -o "$work/h" "$here/harness.c" "$target/debug/libms_rt.a" -lpthread -ldl -lm
fail() { echo "FAIL: $*" >&2; exit 1; }

out=$("$work/h" ok 2>"$work/err") && st=0 || st=$?
[ "$st" = 3 ] || fail "ok: exit $st"
[ "$out" = "héllo" ] || fail "ok: stdout '$out'"

"$work/h" fault >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 70 ] || fail "fault: exit $st"
expected=$(printf 'boom\n  at t.ms:3 in inner\n  at t.ms:3 in inner\n  at t.ms:3 in inner\n  at t.ms:9 in outer\ncleanup b\ncleanup a\n')
# cleanups run before the report is written; accept either relative order of the two streams
grep -q '^boom' "$work/err" || fail "fault: message missing"
grep -q 'in outer' "$work/err" || fail "fault: frames missing"
[ "$(grep -n 'cleanup' "$work/err" | head -1 | cut -d: -f2)" = "cleanup b" ] || fail "fault: cleanup order"

"$work/h" badexit >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 70 ] || fail "badexit: exit $st"
grep -q 'main exit code must be between 0 and 125' "$work/err" || fail "badexit: message"

"$work/h" deep >/dev/null 2>&1 || fail "deep: 199990 nested calls must work"
"$work/h" toodeep >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 70 ] || fail "toodeep: exit $st"
grep -q 'call depth limit exceeded (200000 nested calls)' "$work/err" || fail "toodeep: message"

[ "$("$work/h" args a b c)" = 3 ] || fail "args"

MS_PROFILE="$work/prof" MS_PERF_MAP=1 "$work/h" busy >/dev/null 2>&1 || true
grep -q 'busy [0-9]' "$work/prof" || fail "profile: no busy samples: $(cat "$work/prof")"
ls /tmp/perf-*.map >/dev/null 2>&1 || fail "profile: perf map missing"
echo "ms-rt e2e: ok"
