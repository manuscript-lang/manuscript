#!/bin/sh
# Compares the C entry validation (compiler/src/check/check_entry.c) with the Rust CLI's: for every single-module
# file that resolves cleanly, `ms check` either prints `Checked` (the C check passes) or the entry diagnostic
# (the C check prints the same line). Files with other errors are left out; the handcrafted cases of
# compiler/tests/entry cover each message. Run from the repository root; the Rust `ms` is target/release/ms
# (or $MS_RUST).
set -eu
out=target/c-compiler/entry
rust=${MS_RUST:-target/release/ms}
rm -rf "$out"
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_entry_dump
bin=target/cmake/test/compiler
{ ls compiler/tests/entry/*.ms; git ls-files 'tests/*.ms' 'examples/*.ms'; } > "$out/files.txt"
tr '\n' '\0' < "$out/files.txt" | xargs -0 "$bin/ms_entry_dump" stdlib > "$out/c.txt"
status=0
compared=0
entries=0
while IFS= read -r line; do
    case "$line" in *": skipped") continue ;; esac
    file=${line%%: ok}
    case "$line" in *": ok") expect=ok ;; *) file=${line%%:*}; expect=entry ;; esac
    first=$("$rust" check "$file" 2>&1 | head -1)
    abs="$PWD/$file"
    case "$expect:$first" in
    ok:Checked*) ;;
    entry:*"entry must declare"*)
        entries=$((entries + 1))
        [ "$first" = "$abs:${line#*:}" ] || { echo "FAIL $file"; echo " rust: $first"; echo " c:    $line"; status=1; }
        ;;
    *) continue ;; # Rust found another error first
    esac
    compared=$((compared + 1))
done < "$out/c.txt"
echo "compared $compared files ($entries entry errors)"
[ "$entries" -gt 0 ] || { echo "no entry error compared"; status=1; }
exit $status
