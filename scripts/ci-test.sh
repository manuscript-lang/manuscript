#!/bin/sh
# Run one shard of the Go test suite. The in-process packages that need the race
# detector run under it, without coverage (race plus coverage instrumentation makes
# timing-sensitive tests such as TestBuildersAppendInLinearTime flaky); every other
# package runs once with coverage. Each test runs exactly once.
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

for package in $split_packages; do
    tests=$("$go_tool" test "$package" -list '^Test' | grep '^Test' |
        awk -v n="$count" -v k="$shard" '(NR - 1) % n == k' | paste -sd'|' -)
    [ -n "$tests" ] || continue
    if printf '%s\n' "$race_packages" | grep -qxF "$package"; then
        "$go_tool" test -race "$package" -run "^($tests)\$"
    else
        run "$(basename "$package")" "" "$package" -run "^($tests)\$"
    fi
done

# Remaining packages are dealt round-robin across shards.
mine() { awk -v n="$count" -v k="$shard" '(NR - 1) % n == k'; }
race_rest=$(printf '%s\n' "$race_packages" | grep -vxF 'github.com/manuscript-lang/manuscript/pkg/compiler' | mine || true)
# shellcheck disable=SC2086
[ -z "$race_rest" ] || "$go_tool" test -race $race_rest
excluded=$(printf '%s\n%s\n' "$race_packages" "$split_packages")
cover_rest=$("$go_tool" list ./... | grep -vxF "$excluded" | mine || true)
# shellcheck disable=SC2086
[ -z "$cover_rest" ] || run rest "" $cover_rest
