#!/bin/sh
# End-to-end runtime checks: builds libms_native.a and drives it from a C harness.
# Usage: crates/ms-rt/tests/e2e/run.sh   (CARGO_TARGET_DIR respected)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/target}
case "$target" in /*) ;; *) target="$root/$target" ;; esac
(cd "$root" && cargo build -q --locked -p ms-native --target-dir "$target")
work=$(mktemp -d)
profile_pid=
trap 'rm -rf "$work"; if [ -n "$profile_pid" ]; then rm -f "/tmp/perf-$profile_pid.map"; fi' EXIT
cc -O1 -g -fno-omit-frame-pointer -fno-optimize-sibling-calls -o "$work/h" "$here/harness.c" "$target/debug/libms_native.a" -lpthread -ldl -lm
fail() { echo "FAIL: $*" >&2; exit 1; }

out=$("$work/h" ok 2>"$work/err") && st=0 || st=$?
[ "$st" = 3 ] || fail "ok: exit $st"
[ "$out" = "héllo" ] || fail "ok: stdout '$out'"

out=$("$work/h" strings 2>"$work/err") || fail "strings: exit $?"
[ "$out" = "héllo from the native C driver" ] || fail "strings: stdout '$out'"

"$work/h" fault >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 67 ] || fail "fault: exit $st"
# cleanups run before the report is written; accept either relative order of the two streams
grep -q '^boom' "$work/err" || fail "fault: message missing"
grep -q 'in outer' "$work/err" || fail "fault: frames missing"
[ "$(grep -n 'cleanup' "$work/err" | head -1 | cut -d: -f2)" = "cleanup b" ] || fail "fault: cleanup order"

"$work/h" badexit >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 67 ] || fail "badexit: exit $st"
grep -q 'main exit code must be between 0 and 125' "$work/err" || fail "badexit: message"

"$work/h" deep >/dev/null 2>&1 || fail "deep: 199990 nested calls must work"
"$work/h" toodeep >/dev/null 2>"$work/err" && st=0 || st=$?
[ "$st" = 67 ] || fail "toodeep: exit $st"
grep -q 'call depth limit exceeded' "$work/err" || fail "toodeep: message"

"$work/h" tasks >"$work/tout" 2>"$work/terr" && st=0 || st=$?
[ "$st" = 0 ] || fail "tasks: exit $st: $(cat "$work/tout" "$work/terr")"
grep -q 'tasks ok' "$work/tout" || fail "tasks: output"
grep -q 'task boom' "$work/tout" || fail "tasks: fault report"
grep -q '^cleanup a' "$work/terr" || fail "tasks: faulting task cleanups"

"$work/h" guard >"$work/gout" 2>"$work/gerr" && st=0 || st=$?
[ "$st" = 0 ] || fail "guard: exit $st: $(cat "$work/gerr")"
grep -q 'guards ok' "$work/gout" || fail "guard: output"
[ "$(grep -c '^cleanup b' "$work/gerr")" = 4 ] || fail "guard: inner cleanups must run once per fault"
[ "$(grep -c '^cleanup a' "$work/gerr")" = 5 ] || fail "guard: cleanups below the guard must wait for the final run"
grep -q 'outer boom' "$work/gout" || fail "guard: outer fault message"

"$work/h" parked >/dev/null 2>"$work/perr" &
pid=$!
sleep 0.5
kill -INT "$pid"
wait "$pid" && st=0 || st=$?
[ "$st" = 130 ] || fail "parked: SIGINT while a task sleeps must exit 130, got $st"
grep -q '^cleanup a' "$work/perr" || fail "parked: cleanups must run on cancellation"

[ "$("$work/h" args a b c)" = 3 ] || fail "args"

MS_PROFILE="$work/prof" MS_PERF_MAP=1 "$work/h" busy >/dev/null 2>&1 &
profile_pid=$!
wait "$profile_pid" || fail "profile: busy failed"
grep -q 'busy [0-9]' "$work/prof" || fail "profile: no busy samples: $(cat "$work/prof")"
[ -s "/tmp/perf-$profile_pid.map" ] || fail "profile: perf map missing"

# The adjacent C benchmark is also a native ABI consumer. Check its results,
# without comparing timings or requiring the Go performance baseline.
cc -O2 -fno-omit-frame-pointer -o "$work/bench" "$here/../bench/bench.c" "$target/debug/libms_native.a" -lpthread -ldl -lm
"$work/bench" >"$work/bench.out" || fail "benchmark: wrong result or exit status"
for name in list_push_int list_sort_int map_insert_int map_get_int string_concat_len; do
    grep -q "^$name [0-9]" "$work/bench.out" || fail "benchmark: $name missing"
done
echo "ms-rt e2e: ok"
