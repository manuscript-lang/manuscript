#!/bin/sh
# Run one shard of the Go test suite with coverage; the in-process packages that
# need the race detector run with it, so each package is compiled and tested once.
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
    flags=
    if printf '%s\n' "$race_packages" | grep -qxF "$package"; then flags=-race; fi
    run "$(basename "$package")" "$flags" "$package" -run "^($tests)\$"
done

# Everything else runs once, on shard 0.
[ "$shard" -eq 0 ] || exit 0
others=$(printf '%s\n' "$race_packages" | grep -vxF 'github.com/manuscript-lang/manuscript/pkg/compiler' || true)
# shellcheck disable=SC2086
[ -z "$others" ] || run race -race $others
excluded=$(printf '%s\n%s\n' "$race_packages" "$split_packages")
# shellcheck disable=SC2046
run rest "" $("$go_tool" list ./... | grep -vxF "$excluded" || true)
