#!/bin/sh
# Compares the C whole-program lowering with the Rust lowering of the same programs (the multi-module fixtures in
# compiler/tests/lower_program/<case>/main.ms and any other entry file named on the command line).
# Run from the repository root. Both sides print one MIR module for the entry file and what it reaches; each function
# is keyed by program, name, signature and the line:column it was declared at (two modules can both declare `bump`),
# and the census says what happened to every function Rust emitted:
#   equal    C lowered it and the text matches
#   differs  C lowered it and the text differs (the script fails)
#   skipped  C lowered nothing for it: it stays with the Rust lowering until the C pass covers it
#   ambiguous  the key is shared by two Rust functions, so it cannot be paired
# A function C lowered that Rust did not emit is `extra` (unreachable from main; not counted against C).
# Loops and `match` are lowered differently on purpose (lower-diff.sh): the dump tool marks them `; divergent`, and
# they are verified, not compared.
set -eu
export LC_ALL=C
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-build --example c_lower_oracle
sh compiler/tests/cbuild.sh ms_lower_dump
dump=${MS_C_BUILD:-target/cmake/test}/compiler/ms_lower_dump

if [ "$#" -gt 0 ]; then
    files="$*"
else
    files=$(find compiler/tests/lower_program -name main.ms | sort)
fi
MS_LOWER_WHY=1 "$dump" stdlib --program $files > "$out/program.c" 2> "$out/program.why" || { grep -v '^why ' "$out/program.why" >&2; exit 1; }
target/release/examples/c_lower_oracle $files > "$out/program.rust" 2>/dev/null

# One line per function: `program name sig line:col|block`, `.N` copy suffixes stripped. The file number of a source
# location is dropped: Rust numbers files by first reference, C by module order, and the line and column say the rest.
keyed() {
    sed -E 's/(@[A-Za-z_][A-Za-z_0-9]*)\.[0-9]+/\1/g; s/ !([0-9]+):([0-9]+:[0-9]+)/ !\2/g' "$1" | awk '
        /^=== / { file = $2; next }
        /^; divergent$/ { looped = 1; next }
        /^fn @/ { name = $2; sub(/\(.*/, "", name); sig = $0; sub(/^fn @[^(]*/, "", sig)
                  loc = sig; sub(/^.* !/, "", loc); sub(/ .*$/, "", loc)
                  sub(/ (ret_borrowed|ret_view|export|!).*$/, "", sig)
                  key = file " " name " " sig " " loc; body = ""; infn = 1 }
        infn { body = body $0 "\\n" }
        infn && /^}/ { print key "|" (looped ? "divergent" : body); infn = 0; looped = 0 }' | sort
}
keyed "$out/program.c" > "$out/program.c.keyed"
keyed "$out/program.rust" > "$out/program.rust.keyed"

# Rust's functions: ambiguous when a key repeats.
cut -d'|' -f1 "$out/program.rust.keyed" | uniq -d > "$out/program.ambiguous"
awk -F'|' -v amb="$out/program.ambiguous" -v cfile="$out/program.c.keyed" '
    BEGIN { while ((getline line < amb) > 0) dup[line] = 1
            while ((getline line < cfile) > 0) { split(line, p, "|"); cbody[p[1]] = substr(line, length(p[1]) + 2) } }
    { key = $1; body = substr($0, length(key) + 2); total++
      if (key in dup) { ambiguous++; next }
      if (!(key in cbody)) { skipped++; print "skipped   " key > "/dev/stderr"; next }
      if (cbody[key] == "divergent") { divergent++; next }
      if (cbody[key] == body) { equal++; next }
      differs++; print "differs   " key > "/dev/stderr" }
    END { printf "%d %d %d %d %d %d\n", total, equal, divergent, skipped, ambiguous, differs }' \
    "$out/program.rust.keyed" 2> "$out/program.report" > "$out/program.census"
read -r total equal divergent skipped ambiguous differs < "$out/program.census"
extra=$(cut -d'|' -f1 "$out/program.c.keyed" | sort | comm -23 - "$(cut -d'|' -f1 "$out/program.rust.keyed" | sort -u | { f=$out/program.rust.keys; cat > "$f"; echo "$f"; })" | wc -l)
echo "census: $total functions in Rust, $equal equal, $divergent divergent (verified only), $differs differ, $skipped skipped (C lowered nothing), $ambiguous ambiguous, $extra C-only"
# Why functions were left out: the call site that gave up (compiler/src/check/lower_body.c lb_unsupported), most common
# first. A caller of a function that failed fails too, so the top entries over-count the root causes.
echo "causes (lowering gave up at, count):"
grep '^why ' "$out/program.why" | awk '{ print $2 }' | sed "s|^$(pwd)/||" | sort | uniq -c | sort -rn | head -8
sort "$out/program.report" | head -30
if [ "$differs" -ne 0 ]; then
    echo "FAIL lower program: functions that differ"
    exit 1
fi
echo "ok   lower program ($equal functions equal)"
