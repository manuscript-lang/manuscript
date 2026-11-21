#!/bin/sh
# `ms build` of programs that have diagnostics, through the Manuscript front, against the Rust command: the front
# renders the checker's errors itself (the C checker, as `ms check` does), so standard output, standard error and the
# exit status must equal the Rust command's, with no Rust `ms` behind the front. Programs the front hands over
# (warnings only, a diagnostic C cannot place) are counted and skipped. A manual check, not part of pull request CI.
# Run from the repository root: `sh src/compiler/tests/build-diag-diff.sh [EVERY]` (every Nth `phase=check` program, default 8).
#   MS_FRONT     the Manuscript front built as `ms` (default target/front/ms)
#   MS_RUST_CLI  the Rust ms (default target/release/ms)
#   MS_LLVM_TOOLS, MS_LLD, MS_LINKER_FILES, MS_RT_LIB  as src/ms/build_run.ms reads them
set -u
every=${1:-8}
front=${MS_FRONT:-target/front/ms}
rust=${MS_RUST_CLI:-target/release/ms}
out=target/c-compiler/build-diag
mkdir -p "$out"
grep -rl "^// conform: .*phase=check" tests/conformance/fixtures --include=*.ms | sort | awk -v n="$every" 'NR % n == 0' > "$out/files.txt"
same=0; handed=0; differ=0
while read -r src; do
    MS_RUST_CLI=/nonexistent "$front" build "$src" -o "$out/program" > "$out/front.out" 2> "$out/front.err"
    status=$?
    if grep -q "cannot run /nonexistent\|cannot run ms-rust" "$out/front.err"; then handed=$((handed + 1)); continue; fi
    "$rust" build "$src" -o "$out/program" > "$out/rust.out" 2> "$out/rust.err"
    if [ "$status" = "$?" ] && cmp -s "$out/front.out" "$out/rust.out" && cmp -s "$out/front.err" "$out/rust.err"; then
        same=$((same + 1))
    else
        differ=$((differ + 1)); echo "DIFF $src"
    fi
done < "$out/files.txt"
echo "build diagnostics: $same same, $handed handed to Rust, $differ differ"
[ "$differ" = 0 ]
