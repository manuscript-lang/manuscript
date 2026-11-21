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
"$dump" stdlib --program $files > "$out/program.c"
target/release/examples/c_lower_oracle $files > "$out/program.rust" 2>/dev/null

# One line per function: `program name sig line:col|block`, `.N` copy suffixes stripped. A location names its file by
# number and Rust and C number them differently (first reference in Rust's body order, import order in C), so each
# `!N:` becomes the file's name from the module's `file N "name"` table. A same-named function in two files is told
# apart by the location it was declared at.
keyed() {
    sed -E 's/(@[A-Za-z_][A-Za-z_0-9]*)\.[0-9]+/\1/g' "$1" | awk -v mode="${2:-body}" '
        function named(line,    out, rest, n, name) {
            out = ""; rest = line
            while (match(rest, / ![0-9]+:/)) {
                n = substr(rest, RSTART + 2, RLENGTH - 3)
                name = (n in files) ? files[n] : n
                out = out substr(rest, 1, RSTART) "!" name ":"
                rest = substr(rest, RSTART + RLENGTH)
            }
            line = out rest
            if (match(line, /^  scope "[^"]*" [0-9]+ /)) { # `scope "name" FILE parent line`: the file of an inlined frame
                n = line; sub(/^  scope "[^"]*" /, "", n); sub(/ .*$/, "", n)
                if (n in files) sub(/" [0-9]+ /, "\" " files[n] " ", line)
            }
            return line
        }
        /^=== / { file = $2; delete files; next }
        /^file [0-9]+ "/ { n = $2; name = $3; gsub(/"/, "", name); files[n] = name; next }
        /^; divergent$/ { looped = 1; next }
        /^fn @/ { $0 = named($0); name = $2; sub(/\(.*/, "", name); sig = $0; sub(/^fn @[^(]*/, "", sig)
                  loc = sig; sub(/^.* !/, "", loc); sub(/ .*$/, "", loc)
                  full = sig; sub(/ !.*$/, "", full)
                  if (mode == "sig") { print file " " name " " loc "|" full; next }
                  sub(/ (ret_borrowed|ret_view|export|!).*$/, "", sig)
                  key = file " " name " " sig " " loc; body = ""; infn = 1; print_head = 1 }
        infn { line = $0; if (!print_head) line = named(line); print_head = 0; body = body line "\\n" }
        infn && /^}/ { print key "|" (looped ? "divergent" : body); infn = 0; looped = 0 }' | sort
}
keyed "$out/program.c" > "$out/program.c.keyed"
keyed "$out/program.rust" > "$out/program.rust.keyed"

# A function both sides emit once (same program, name and declaration) must have the same signature: parameter
# and result types, `move` modes and the `ret_borrowed`, `ret_view` and `export` flags, which callers lowered by
# either side rely on. The body comparison below keys on the types, so such a function would only show as skipped.
keyed "$out/program.c" sig > "$out/program.c.sigs"
keyed "$out/program.rust" sig > "$out/program.rust.sigs"
for side in c rust; do cut -d'|' -f1 "$out/program.$side.sigs" | sort | uniq -u > "$out/program.$side.once"; done
sort "$out/program.c.sigs" > "$out/program.c.sigs.sorted"
sort "$out/program.rust.sigs" > "$out/program.rust.sigs.sorted"
sigdiffs=$(awk -F'|' -v c="$out/program.c.once" -v r="$out/program.rust.once" '
    BEGIN { while ((getline l < c) > 0) inc[l] = 1; while ((getline l < r) > 0) inr[l] = 1 }
    FNR == NR { if ($1 in inc && $1 in inr) csig[$1] = $2; next }
    ($1 in csig) && csig[$1] != $2 { printf "signature %s\n  C:    %s\n  Rust: %s\n", $1, csig[$1], $2; bad++ }
    END { exit bad > 0 }' "$out/program.c.sigs.sorted" "$out/program.rust.sigs.sorted" 2>&1) || {
    echo "FAIL lower program signatures: C and Rust differ on a function both emit"
    echo "$sigdiffs" | head -20
    exit 1
}

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
sort "$out/program.report" | head -30
if [ "$differs" -ne 0 ]; then
    echo "FAIL lower program: functions that differ"
    exit 1
fi
echo "ok   lower program ($equal functions equal)"
