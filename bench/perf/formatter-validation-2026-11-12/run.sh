#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
out=${1:?provide a new output directory}
mkdir "$out"
out=$(cd "$out" && pwd)
baseline=${BASELINE:-37a14ba5797bed73a66d1350bee03d2238c63a20}
rustc=${RUSTC:-rustc}
mkdir "$out/base"
git archive "$baseline" crates/ms-syntax | tar -x -C "$out/base"
for variant in base parse; do
    source="$root/crates/ms-syntax/src/lib.rs"
    if [[ "$variant" == base ]]; then source="$out/base/crates/ms-syntax/src/lib.rs"; fi
    "$rustc" --edition=2024 --crate-name ms_syntax --crate-type rlib -C opt-level=3 -C panic=abort "$source" -o "$out/lib-$variant.rlib"
    "$rustc" --edition=2024 -C opt-level=3 -C panic=abort --extern "ms_syntax=$out/lib-$variant.rlib" bench/perf/formatter-validation-2026-11-12/main.rs -o "$out/format-$variant"
done
for round in 0 1 2 3; do
    order=(base parse)
    if (( round % 2 )); then order=(parse base); fi
    for variant in "${order[@]}"; do
        "$out/format-$variant" > "$out/format-$round-$variant.txt"
    done
done
