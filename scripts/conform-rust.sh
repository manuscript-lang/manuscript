#!/bin/sh
# Build the Rust ms and run the conformance corpus against it, allowing the failures listed in
# tests/conformance/rust-expect-fail.txt plus the host's expect-fail.<os>.txt.
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

cargo build --release --locked -p ms-cli -p ms-conform

mkdir -p .artifacts
allow=.artifacts/conform-rust-expect-fail.txt
cp tests/conformance/rust-expect-fail.txt "$allow"
if [ -f "tests/conformance/rust/expect-fail.$host.txt" ]; then
    cat "tests/conformance/rust/expect-fail.$host.txt" >> "$allow"
fi

"target/release/ms-conform$exe" run --ms "$repository/target/release/ms$exe" \
    --phase run,check,test --exclude-tag aliasing --expect-fail "$allow" --quiet \
    --markdown .artifacts/conform-rust.md "$@"
