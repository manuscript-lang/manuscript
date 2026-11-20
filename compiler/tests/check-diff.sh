#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
#   scope   the name-resolution diagnostics of every fixture that imports only `@std/` modules
#   bodies  the expression types of the functions whose bodies the C pass checks (only those: it
#           leaves a function with an unhandled construct to the Rust checker), with no Rust diagnostic inside
#   effect directives  the `// ms: effect` and `allow_effect` lines of every .ms file in the repository
#   effect graph  reachability and violations over generated reference graphs (MS_EFFECT_GRAPHS, default 500)
# The set of compared things grows with each checker pass the C side gains; a pass is not
# "ported" until its line here passes.
set -eu
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-check --example c_oracle --example c_oracle_effects
oracle=target/release/examples/c_oracle
effects_oracle=target/release/examples/c_oracle_effects

cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Icompiler/include -Iruntime/include"
cc $cflags compiler/src/libms.c compiler/tools/ms_check_dump.c -o "$out/check-dump" -lm
cc $cflags compiler/src/libms.c compiler/tests/types_test.c -o "$out/types-test" -lm
cc $cflags compiler/src/libms.c compiler/tests/ownership_test.c -o "$out/ownership-test" -lm
cc $cflags compiler/src/libms.c compiler/tests/recursion_test.c -o "$out/recursion-test" -lm
"$out/ownership-test"
"$out/types-test"
"$out/recursion-test"

status=0
"$oracle" > "$out/tables.rust"
"$out/check-dump" stdlib > "$out/tables.c"
if cmp -s "$out/tables.rust" "$out/tables.c"; then
    echo "ok   tables ($(grep -c '^module' "$out/tables.rust") native modules)"
else
    echo "FAIL tables: first difference"
    diff "$out/tables.rust" "$out/tables.c" | head -20 || true
    status=1
fi
# Name resolution: the diagnostics of the families the C pass implements, for the scope fixtures
# and the whole conformance corpus. The files must produce some, or the comparison proves nothing.
files=$(find compiler/tests/scope tests/conformance/fixtures -name '*.ms' | sort)
"$oracle" --scope $files > "$out/scope.rust"
"$out/check-dump" stdlib --scope $files > "$out/scope.c"
# The Rust checker stops before every pass when desugaring an inherent `impl` fails; the C
# checker does not desugar yet, so those files are left out of the comparison until it does.
drop_unchecked() {
    awk -v list="$out/scope.unchecked" '
        BEGIN { while ((getline line < list) > 0) skip[line] = 1 }
        /^== / { dropped = ($2 in skip) }
        !dropped { print }' "$1"
}
awk '/^== / { file = $2 } /^unchecked$/ { print file }' "$out/scope.rust" > "$out/scope.unchecked"
drop_unchecked "$out/scope.rust" > "$out/scope.rust.kept"
drop_unchecked "$out/scope.c" > "$out/scope.c.kept"
mv "$out/scope.rust.kept" "$out/scope.rust"
mv "$out/scope.c.kept" "$out/scope.c"
if cmp -s "$out/scope.rust" "$out/scope.c" && [ -s "$out/scope.rust" ]; then
    echo "ok   scope ($(grep -c "^[0-9]*:[0-9]*: " "$out/scope.rust") diagnostics, $(grep -c "^typeref" "$out/scope.rust") type references)"
else
    echo "FAIL scope: first difference"
    diff "$out/scope.rust" "$out/scope.c" | head -20 || true
    status=1
fi

# Function bodies: the facts of every function the C pass checked, against the Rust checker's.
# Each line is keyed by file and function so that only the functions C claims are compared; a Rust
# diagnostic inside one of them shows as `dirty`, which the C side never prints.
"$oracle" --bodies $files > "$out/bodies.rust"
"$out/check-dump" stdlib --bodies $files > "$out/bodies.c"
keyed() {
    awk '/^== / { file = $2; key = ""; next } /^fn / { key = file " " $2 } key != "" { print key "|" $0 }' "$1"
}
keyed "$out/bodies.c" > "$out/bodies.c.keyed"
cut -d'|' -f1 "$out/bodies.c.keyed" | sort -u > "$out/bodies.keys"
keyed "$out/bodies.rust" | awk -F'|' -v list="$out/bodies.keys" '
    BEGIN { while ((getline line < list) > 0) keep[line] = 1 }
    $1 in keep' > "$out/bodies.rust.keyed"
if cmp -s "$out/bodies.rust.keyed" "$out/bodies.c.keyed" && [ -s "$out/bodies.c.keyed" ]; then
    echo "ok   bodies ($(wc -l < "$out/bodies.keys") functions, $(grep -c '|expr ' "$out/bodies.c.keyed") expressions)"
else
    echo "FAIL bodies: first difference"
    diff "$out/bodies.rust.keyed" "$out/bodies.c.keyed" | head -20 || true
    status=1
fi

cc $cflags compiler/src/libms.c compiler/tools/ms_effect_dump.c -o "$out/effect-dump" -lm
cc -std=c11 -O1 -Wall -Wextra -Werror compiler/tests/effect_graph_gen.c -o "$out/effect-graph-gen"
# Effect directives on every source file, then generated graphs, each compared with the Rust result.
# The fixture is written here because the repository forbids carriage returns in stored files: it has CRLF
# and CR-only line ends, non-breaking and em spaces, empty names and directives without a separator.
printf '// ms: allow_effect std.fs.read\r\n//   ms:  allow_effect   db.*  \r\n\r\n\302\240// ms: effect a.b\342\200\203\n// ms: effect  \n// ms:effect x\n// ms: allow_effect\nfn f() {}\n\n// ms: allow_effect *\n\n// ms: effect z\r\r\nfn g() {}\n// plain\nlet x = 1' > "$out/directives-fixture.ms"
{ find . -name '*.ms' -not -path './target/*' -not -path './.git/*' | sort; echo "$out/directives-fixture.ms"; } > "$out/sources.txt"
xargs "$effects_oracle" directives < "$out/sources.txt" > "$out/directives.rust"
xargs "$out/effect-dump" directives < "$out/sources.txt" > "$out/directives.c"
if cmp -s "$out/directives.rust" "$out/directives.c"; then
    echo "ok   effect directives ($(grep -c '^file' "$out/directives.rust") files)"
else
    echo "FAIL effect directives: first difference"
    diff "$out/directives.rust" "$out/directives.c" | head -20 || true
    status=1
fi

graphs=${MS_EFFECT_GRAPHS:-500}
seed=1
graph_status=0
while [ "$seed" -le "$graphs" ]; do
    "$out/effect-graph-gen" "$seed" > "$out/graph.txt"
    "$effects_oracle" graph < "$out/graph.txt" > "$out/graph.rust"
    "$out/effect-dump" graph < "$out/graph.txt" > "$out/graph.c"
    if ! cmp -s "$out/graph.rust" "$out/graph.c"; then
        echo "FAIL effect graph, seed $seed (graph in $out/graph.txt): first difference"
        diff "$out/graph.rust" "$out/graph.c" | head -20 || true
        graph_status=1
        break
    fi
    seed=$((seed + 1))
done
if [ "$graph_status" -eq 0 ]; then
    echo "ok   effect graph ($graphs generated graphs)"
else
    status=1
fi
exit $status
