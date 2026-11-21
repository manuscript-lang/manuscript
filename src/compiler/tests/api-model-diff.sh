#!/bin/sh
# Compares the standard library's API model of the C checker (`ms_api_model STDLIB`) with the Rust
# `ms-tooling` example `api_model`, byte for byte.
#   sh src/compiler/tests/api-model-diff.sh API_MODEL_BINARY RUST_MODEL_BINARY
# RUST_MODEL_BINARY is the built example (`cargo build -p ms-tooling --example api_model`, then
# target/debug/examples/api_model).
set -eu
model=$(realpath "$1")
rust=$(realpath "$2")
stdlib=$(realpath "$(dirname "$0")/../../stdlib")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$rust" >"$work/rust.json"
"$model" "$stdlib" >"$work/c.json"
if ! cmp -s "$work/rust.json" "$work/c.json"; then
	echo "api model differs from the Rust model:"
	diff "$work/rust.json" "$work/c.json" | head -40
	exit 1
fi
echo "api model: C and Rust agree on $(grep -c '"declaration":' "$work/c.json") declarations"
