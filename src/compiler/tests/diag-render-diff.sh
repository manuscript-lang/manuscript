#!/bin/sh
# Checks the C diagnostic renderer against frozen goldens: for every src/compiler/tests/diag-render/NNN.src (a source
# that fails to parse), the terminal report (NNN.txt) and the --json document (NNN.json) the Rust `ms check`
# printed for it as NNN.ms. Regenerate them with src/compiler/tests/diag-render-regen.sh. Run from the repository root.
set -eu
out=target/c-compiler/diag-render
rm -rf "$out"
mkdir -p "$out"
sh src/compiler/tests/cbuild.sh ms_diag_render_dump
bin=target/cmake/test/compiler
dir=src/compiler/tests/diag-render
status=0
compared=0
for src in "$dir"/*.src; do
    id=$(basename "$src" .src)
    cp "$src" "$out/$id.ms"
    "$bin/ms_diag_render_dump" text "$out/$id.ms" "$PWD/$out/$id.ms" "$id.ms" | sed "s#$PWD/$out/##" > "$out/$id.txt"
    "$bin/ms_diag_render_dump" json "$out/$id.ms" "$PWD/$out/$id.ms" "$id.ms" > "$out/$id.json"
    compared=$((compared + 1))
    cmp -s "$out/$id.txt" "$dir/$id.txt" || { echo "FAIL text $id"; diff "$dir/$id.txt" "$out/$id.txt" | head -8; status=1; }
    cmp -s "$out/$id.json" "$dir/$id.json" || { echo "FAIL json $id"; diff "$dir/$id.json" "$out/$id.json" | head -8; status=1; }
done
echo "compared $compared failing files"
[ "$compared" -gt 0 ] || { echo "no fixture"; status=1; }
exit $status
