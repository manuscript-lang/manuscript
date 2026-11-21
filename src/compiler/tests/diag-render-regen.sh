#!/bin/sh
# Regenerates the goldens of diag-render-diff.sh from a Rust `ms` ($MS_RUST, default target/release/ms): the text
# report (paths relative) and --json document of `ms check NNN.ms` for each src/compiler/tests/diag-render/NNN.src. Run from the
# repository root. Adding a case is adding a NNN.src and running this.
set -eu
rust=$(cd "$(dirname "${MS_RUST:-target/release/ms}")" && pwd)/$(basename "${MS_RUST:-target/release/ms}")
dir=$PWD/src/compiler/tests/diag-render
tmp=$(mktemp -d)
for src in "$dir"/*.src; do
    id=$(basename "$src" .src)
    cp "$src" "$tmp/$id.ms"
    (cd "$tmp" && "$rust" check "$id.ms" 2>&1 > /dev/null | sed "s#$tmp/##" > "$dir/$id.txt" || true)
    (cd "$tmp" && "$rust" check "$id.ms" --json > "$dir/$id.json" 2> /dev/null || true)
done
rm -rf "$tmp"
