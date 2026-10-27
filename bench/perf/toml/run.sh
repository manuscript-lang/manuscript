#!/bin/sh
# Compares @std/toml parse with Rust's toml crate on the same generated document.
# Usage: MS=./target/release/ms sh bench/perf/toml/run.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
MS=$(command -v "${MS:-ms}")
MS=$(cd "$(dirname "$MS")" && pwd)/$(basename "$MS")
(cd "$here/ms" && "$MS" run src/main.ms)
(cd "$here/rust" && cargo run --release --quiet)
