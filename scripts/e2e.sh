#!/bin/sh
# Every fixture under tests/e2e/testdata against the Rust ms on this host (`make e2e`, usable without make).
# accept/ fixtures pass `ms test`; reject/ fixtures fail `ms check`.
# E2E_BUILD_TYPE picks the build type (default Debug). Extra arguments are fixture paths to run instead.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

exe=
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) exe=.exe ;;
esac
ms="$repository/target/debug/ms$exe"
build_type=${E2E_BUILD_TYPE:-Debug}

cargo build --locked -q -p ms-cli

if [ "$#" -gt 0 ]; then
    fixtures=$*
else
    fixtures=$(ls tests/e2e/testdata/accept/*.ms tests/e2e/testdata/reject/*.ms)
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
            if ! "$ms" test "$fixture" --build-type "$build_type" >"$err" 2>&1; then
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
