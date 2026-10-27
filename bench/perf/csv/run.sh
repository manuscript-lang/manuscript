#!/bin/sh
# Compares @std/csv parse with Rust's csv crate on the same generated rows.
# Usage: MS=./target/release/ms sh bench/perf/csv/run.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
MS=$(command -v "${MS:-ms}")
MS=$(cd "$(dirname "$MS")" && pwd)/$(basename "$MS")
(cd "$here/ms" && "$MS" run src/main.ms)
(cd "$here/rust" && cargo run --release --quiet)
