#!/bin/sh
# The frozen corpus against the Rust ms on this host: `make conform-rust` without make.
# Known failures: tests/conformance/rust-expect-fail.txt plus rust-expect-fail.<os>.txt.
# Usage: conform-rust.sh [extra ms-conform run flags]
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

case "$(uname -s)" in
    Linux) host=linux ;;
    Darwin) host=macos ;;
    MINGW*|MSYS*|CYGWIN*) host=windows ;;
    *) echo "Unsupported host: $(uname -s)" >&2; exit 1 ;;
esac
exe=
if [ "$host" = windows ]; then exe=.exe; fi

cargo build --locked -q -p ms-cli -p ms-conform

mkdir -p .artifacts
allow=.artifacts/conform-rust-expect-fail.txt
cp tests/conformance/rust-expect-fail.txt "$allow"
if [ -f "tests/conformance/rust-expect-fail.$host.txt" ]; then
    cat "tests/conformance/rust-expect-fail.$host.txt" >> "$allow"
fi

"target/debug/ms-conform$exe" lint
"target/debug/ms-conform$exe" run --ms "$repository/target/debug/ms$exe" \
    --phase run,check,test --exclude-tag aliasing --expect-fail "$allow" --quiet \
    --markdown .artifacts/conform-rust.md "$@"
