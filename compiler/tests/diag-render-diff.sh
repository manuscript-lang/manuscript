#!/bin/sh
# Compares the C diagnostic renderer with the Rust CLI's, byte for byte: the terminal report and the
# --json document of `ms check` on every repository file that fails to parse, and on mutated copies.
# Run from the repository root; MS_FUZZ sets the mutant count (default 400). The Rust `ms` is
# target/release/ms (or $MS_RUST).
set -eu
out=target/c-compiler/diag-render
rust=${MS_RUST:-target/release/ms}
fuzz=${MS_FUZZ:-400}
rm -rf "$out"
mkdir -p "$out/fuzz"
sh compiler/tests/cbuild.sh ms_diag_render_dump mutate
bin=target/cmake/test/compiler
git ls-files '*.ms' > "$out/files.txt"
"$bin/mutate" "$out/fuzz" "$fuzz" "${MS_FUZZ_SEED:-1}" "$out/files.txt"
ls "$out"/fuzz/*.ms > "$out/fuzz.txt"
cat "$out/files.txt" >> "$out/fuzz.txt"
status=0
compared=0
while read -r file; do
    dir=$(cd "$(dirname "$file")" && pwd)
    name=$(basename "$file")
    "$bin/ms_diag_render_dump" text "$file" "$dir/$name" "$name" > "$out/c.txt"
    [ -s "$out/c.txt" ] || continue
    # The file is named the way the Rust CLI is given it: by its base name from its directory.
    "$bin/ms_diag_render_dump" json "$file" "$dir/$name" "$name" > "$out/c.json"
    (cd "$dir" && "$OLDPWD/$rust" check "$name" 2> "$OLDPWD/$out/r.txt" > /dev/null || true)
    (cd "$dir" && "$OLDPWD/$rust" check "$name" --json > "$OLDPWD/$out/r.json" 2> /dev/null || true)
    # The Rust CLI recovers past the first parse error and may report more; the renderer is compared on the
    # files where both stop at the first.
    [ "$(grep -c ': parse: ' "$out/r.txt")" -eq 1 ] || continue
    compared=$((compared + 1))
    cmp -s "$out/c.txt" "$out/r.txt" || { echo "FAIL text $file"; diff "$out/r.txt" "$out/c.txt" | head -8; status=1; }
    cmp -s "$out/c.json" "$out/r.json" || { echo "FAIL json $file"; diff "$out/r.json" "$out/c.json" | head -8; status=1; }
done < "$out/fuzz.txt"
echo "compared $compared failing files"
[ "$compared" -gt 0 ] || { echo "no file failed to parse"; status=1; }
exit $status
