#!/bin/sh
# Every fixture under tests/e2e/testdata against the Rust ms on this host (`make e2e`, usable without make).
# accept/ fixtures pass `ms test`; reject/ fixtures fail `ms check`.
# Known failures are listed in tests/e2e/expect-fail.txt. E2E_BUILD_TYPE picks the build type (default Release,
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

cargo build --locked -q -p ms-cli

if [ "$#" -gt 0 ]; then
    fixtures=$*
else
    fixtures=$(ls tests/e2e/testdata/accept/*.ms tests/e2e/testdata/stdlib/*.ms tests/e2e/testdata/reject/*.ms)
fi

err=$(mktemp)
failed=0
count=0
for fixture in $fixtures; do
    count=$((count + 1))
    case "$fixture" in
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
rm -f "$err"
echo "e2e: $count fixtures, $failed failed ($build_type)"
[ "$failed" -eq 0 ]
