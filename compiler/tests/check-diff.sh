#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
#   scope   the name-resolution diagnostics of every fixture that imports only `@std/` modules
#   effect directives  the `// ms: effect` and `allow_effect` lines of every .ms file in the repository
#   desugar  inherent impls rewritten, as project and bundled modules and with foreign types
#   methods  the operations of interfaces, over every file that declares one
#   effect graph  reachability and violations over generated reference graphs (MS_EFFECT_GRAPHS, default 500)
# The set of compared things grows with each checker pass the C side gains; a pass is not
# "ported" until its line here passes.
set -eu
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-check --example c_oracle --example c_oracle_effects --example c_oracle_desugar --example c_oracle_methods
oracle=target/release/examples/c_oracle
effects_oracle=target/release/examples/c_oracle_effects
desugar_oracle=target/release/examples/c_oracle_desugar
methods_oracle=target/release/examples/c_oracle_methods

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

cc $cflags compiler/src/libms.c compiler/tools/ms_desugar_dump.c -o "$out/desugar-dump" -lm
# The corpus: every source file that writes a method, a property marker or an impl, plus a fixture for
# what no file does (a method on an interface, methods on types another module declares).
printf 'type Remote[T]:\n\tvalue: T\n\nenum Mode:\n\tFast\n\tSlow\n' > "$out/desugar-foreign.ms"
printf 'interface Shape:\n\tfn area() Int\n\nfn Shape.twice() Int:\n\treturn 2\n\nfn Remote[T].get() T:\n\treturn self.value\n\nfn Mode.label() String:\n\treturn "m"\n\nfn Remote.broken() Int:\n\treturn 1\n' > "$out/desugar-fixture.ms"
xargs grep -lE '^(var )?fn (move )?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\.|^impl |^// ms: (data|clonable)' < "$out/sources.txt" > "$out/desugar-sources.txt"
echo "$out/desugar-fixture.ms" >> "$out/desugar-sources.txt"
desugar_status=0
for mode in user std; do
    xargs "$desugar_oracle" "$mode" < "$out/desugar-sources.txt" > "$out/desugar-$mode.rust"
    xargs "$out/desugar-dump" "$mode" < "$out/desugar-sources.txt" > "$out/desugar-$mode.c"
    cmp -s "$out/desugar-$mode.rust" "$out/desugar-$mode.c" || desugar_status=1
done
"$desugar_oracle" foreign "$out/desugar-foreign.ms" "$out/desugar-fixture.ms" > "$out/desugar-foreign.rust"
"$out/desugar-dump" foreign "$out/desugar-foreign.ms" "$out/desugar-fixture.ms" > "$out/desugar-foreign.c"
cmp -s "$out/desugar-foreign.rust" "$out/desugar-foreign.c" || desugar_status=1
if [ "$desugar_status" -eq 0 ]; then
    echo "ok   desugar ($(grep -c '^===' "$out/desugar-user.rust") files, $(grep -c '^inherent' "$out/desugar-user.rust") errors)"
else
    echo "FAIL desugar: first difference"
    for part in user std foreign; do
        diff "$out/desugar-$part.rust" "$out/desugar-$part.c" | cut -c1-200 | head -10 || true
    done
    status=1
fi

cc $cflags -Icompiler/tools compiler/src/libms.c compiler/tools/ms_methods_dump.c -o "$out/methods-dump" -lm
# Every file that declares an interface, plus a fixture for what no file does: a repeated operation
# and a type parameter that shadows one.
printf 'interface Shape[T]:\n\tfn area() Int\n\tfn area() Int\n\tfn map[T]() T\n\tfn pair[U, U](other: Self) U\n\tfn nest(other: List[Self]) Int\n' > "$out/methods-fixture.ms"
xargs grep -lE '^interface |^(var )?fn (move )?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\.' < "$out/sources.txt" > "$out/methods-sources.txt"
echo "$out/methods-fixture.ms" >> "$out/methods-sources.txt"
xargs "$methods_oracle" < "$out/methods-sources.txt" > "$out/methods.rust"
xargs "$out/methods-dump" stdlib < "$out/methods-sources.txt" > "$out/methods.c"
if cmp -s "$out/methods.rust" "$out/methods.c"; then
    echo "ok   methods ($(grep -c '^==' "$out/methods.rust") files, $(grep -c '^op ' "$out/methods.rust") operations)"
else
    echo "FAIL methods: first difference"
    diff "$out/methods.rust" "$out/methods.c" | cut -c1-200 | head -10 || true
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
