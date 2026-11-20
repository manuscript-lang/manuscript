#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
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

cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Iruntime/include -Icompiler/include"
cc $cflags compiler/src/libms.c compiler/tools/ms_check_dump.c -o "$out/check-dump"
cc $cflags compiler/src/libms.c compiler/tests/types_test.c -o "$out/types-test"
cc $cflags compiler/src/libms.c compiler/tools/ms_effect_dump.c -o "$out/effect-dump"
cc -std=c11 -O1 -Wall -Wextra -Werror compiler/tests/effect_graph_gen.c -o "$out/effect-graph-gen"
"$out/types-test"

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
