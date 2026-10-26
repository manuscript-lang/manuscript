#!/bin/sh
# Every fixture under tests/e2e/testdata against the Rust ms on this host (`make e2e`, usable without make).
# accept/ and stdlib/ fixtures pass `ms test`; reject/ fixtures fail `ms check`. A project directory runs its
# conformance_test.ms with `ms test`; otherwise its main.ms must check, and run to expected-output.txt when that exists.
# project_check is a project whose check must fail.
# Known failures are listed in tests/e2e/expect-fail.txt (Windows-only ones in expect-fail.windows.txt). E2E_BUILD_TYPE picks the build type (default Release,
# which the deep-nesting fixtures need to finish quickly). Extra arguments are fixture paths to run instead.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

exe=
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) exe=.exe ;;
esac
ms="$repository/target/debug/ms$exe"
build_type=${E2E_BUILD_TYPE:-Release}
expected=tests/e2e/expect-fail.txt
# Windows hosts also expect the failures in expect-fail.windows.txt.
if [ -n "$exe" ]; then
    expected=$(mktemp)
    cat tests/e2e/expect-fail.txt tests/e2e/expect-fail.windows.txt >"$expected"
fi

cargo xtask runtime >/dev/null
cargo build --locked -q -p ms-cli --target-dir "$repository/target"

if [ "$#" -gt 0 ]; then
    fixtures=$*
else
    fixtures=$(ls -d tests/e2e/testdata/accept/*.ms tests/e2e/testdata/stdlib/*.ms tests/e2e/testdata/reject/*.ms tests/e2e/testdata/projects/*)
fi

# A project directory passes when its tests pass, or its main.ms checks and prints expected-output.txt.
project_passes() {
    dir=$1
    if [ -f "$dir/conformance_test.ms" ]; then
        (cd "$dir" && "$ms" test conformance_test.ms --build-type "$build_type") >"$err" 2>&1
    elif [ -f "$dir/ms.toml" ]; then
        "$ms" check "$dir/ms.toml" >"$err" 2>&1
    else
        "$ms" check "$dir/main.ms" >"$err" 2>&1 || return 1
        [ -f "$dir/expected-output.txt" ] || return 0
        (cd "$dir" && "$ms" run main.ms --build-type "$build_type") >"$err.out" 2>&1 || return 1
        cmp -s "$err.out" "$dir/expected-output.txt"
    fi
}

err=$(mktemp)
failed=0
count=0
for fixture in $fixtures; do
    count=$((count + 1))
    case "$fixture" in
        */projects/project_check)
            if project_passes "$fixture"; then
                echo "FAIL $fixture: a reject project checked clean" >&2
                failed=$((failed + 1))
            fi
            ;;
        */projects/*)
            listed=$(grep -v '^#' "$expected" | cut -f1 | grep -Fx "$fixture" || true)
            if project_passes "$fixture"; then
                if [ -n "$listed" ]; then
                    echo "FAIL $fixture: listed as failing but passes" >&2
                    failed=$((failed + 1))
                fi
            elif [ -z "$listed" ]; then
                echo "FAIL $fixture" >&2
                grep -v '^RUN\|^PASS' "$err" | head -8 >&2
                failed=$((failed + 1))
            fi
            ;;
        */reject/*)
            if "$ms" check "$fixture" >/dev/null 2>&1; then
                echo "FAIL $fixture: a reject fixture checked clean" >&2
                failed=$((failed + 1))
            fi
            ;;
        *)
            # The listed failures: a whole fixture, or the tests its regex names.
            entry=$(grep -v '^#' "$expected" | awk -F '\t' -v f="$fixture" '$1 == f { print "listed\t" $2 }')
            pattern=${entry#listed?}
            if [ -n "$entry" ] && [ -z "$pattern" ]; then
                if "$ms" test "$fixture" --build-type "$build_type" >/dev/null 2>&1; then
                    echo "FAIL $fixture: listed as failing but passes" >&2
                    failed=$((failed + 1))
                fi
            elif [ -n "$pattern" ]; then
                # A missing selection also exits nonzero; it is not evidence of a
                # failing test. Match full module::name identities before running.
                if ! "$ms" test "$fixture" --build-type "$build_type" --list --match "$pattern" >"$err" 2>&1; then
                    echo "FAIL $fixture: expected-failure pattern does not select runnable tests: $pattern" >&2
                    head -8 "$err" >&2
                    failed=$((failed + 1))
                    continue
                fi
                if ! "$ms" test "$fixture" --build-type "$build_type" --exclude "$pattern" >"$err" 2>&1; then
                    echo "FAIL $fixture" >&2
                    grep -v '^RUN\|^PASS' "$err" | head -8 >&2
                    failed=$((failed + 1))
                fi
                if "$ms" test "$fixture" --build-type "$build_type" --match "$pattern" >/dev/null 2>&1; then
                    echo "FAIL $fixture: $pattern is listed as failing but passes" >&2
                    failed=$((failed + 1))
                fi
            elif ! "$ms" test "$fixture" --build-type "$build_type" >"$err" 2>&1; then
                echo "FAIL $fixture" >&2
                grep -v '^RUN\|^PASS' "$err" | head -8 >&2
                failed=$((failed + 1))
            fi
            ;;
    esac
done
rm -f "$err" "$err.out"
[ -z "$exe" ] || rm -f "$expected"
echo "e2e: $count fixtures, $failed failed ($build_type)"
[ "$failed" -eq 0 ]
