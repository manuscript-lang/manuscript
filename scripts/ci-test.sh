#!/bin/sh
# Run one shard of the Go test suite. The in-process packages that need the race
# detector run under it, without coverage (race plus coverage instrumentation makes
# timing-sensitive tests such as TestBuildersAppendInLinearTime flaky); every other
# package runs once with coverage. Each test runs exactly once. Groups run concurrently.
# Usage: ci-test.sh SHARD COUNT
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"
shard=${1:?shard index}
count=${2:?shard count}
go_tool=$repository/toolchain/go/bin/go
export MANUSCRIPT_EXAMPLES_NATIVE=1
mkdir -p .artifacts/coverage
coverpkg=$("$go_tool" list ./... | paste -sd, -)

# Packages whose tests run under the race detector.
race_packages=$("$go_tool" list ./internal/debugger ./pkg/runtime ./pkg/checker ./pkg/compiler ./pkg/project ./internal/cli ./pkg/tooling/...)
# Packages split across shards because a single test binary dominates wall time.
split_packages='github.com/manuscript-lang/manuscript/pkg/compiler
github.com/manuscript-lang/manuscript/tests/e2e'

run() { # name, extra flags, packages...
    name=$1
    flags=$2
    shift 2
    # shellcheck disable=SC2086
    "$go_tool" test $flags -covermode=atomic -coverpkg="$coverpkg" -coverprofile=".artifacts/coverage/$name.out" "$@"
}

# Each group runs in the background (the runner has several cores and most test
# binaries are mostly serial); output is replayed per group afterwards.
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT HUP INT TERM
pids=''
start() { # name, command...
    name=$1
    shift
    ("$@" > "$logs/$name.log" 2>&1 && echo 0 > "$logs/$name.status" || echo 1 > "$logs/$name.status") &
    pids="$pids $name"
}

for package in $split_packages; do
    tests=$("$go_tool" test "$package" -list '^Test' | grep '^Test' |
        awk -v n="$count" -v k="$shard" '(NR - 1) % n == k' | paste -sd'|' -)
    [ -n "$tests" ] || continue
    name=$(basename "$package")
    if printf '%s\n' "$race_packages" | grep -qxF "$package"; then
        start "$name" "$go_tool" test -race "$package" -run "^($tests)\$"
    else
        start "$name" run "$name" "" "$package" -run "^($tests)\$"
    fi
done

# Remaining packages are dealt round-robin across shards.
mine() { awk -v n="$count" -v k="$shard" '(NR - 1) % n == k'; }
race_rest=$(printf '%s\n' "$race_packages" | grep -vxF 'github.com/manuscript-lang/manuscript/pkg/compiler' | mine || true)
# shellcheck disable=SC2086
[ -z "$race_rest" ] || start race-rest "$go_tool" test -race $race_rest
excluded=$(printf '%s\n%s\n' "$race_packages" "$split_packages")
cover_rest=$("$go_tool" list ./... | grep -vxF "$excluded" | mine || true)
# shellcheck disable=SC2086
[ -z "$cover_rest" ] || start cover-rest run rest "" $cover_rest

wait
status=0
for name in $pids; do
    echo "::group::$name"
    cat "$logs/$name.log"
    echo '::endgroup::'
    [ "$(cat "$logs/$name.status")" = 0 ] || { echo "FAILED: $name" >&2; status=1; }
done
exit "$status"
