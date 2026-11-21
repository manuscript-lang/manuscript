#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
#   scope   the name-resolution diagnostics of every fixture that imports only `@std/` modules
#   bodies  the expression types of the functions whose bodies the C pass checks (only those: it
#           leaves a function with an unhandled construct to the Rust checker), with the diagnostics inside each
#   ownership  the ownership diagnostics inside the functions the C walk handles (moves, borrows, returns)
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

sh compiler/tests/cbuild.sh ms_check_dump types_test ownership_test recursion_test ty_algebra_test infer_test implements_test ms_effect_dump effect_graph_gen ms_desugar_dump ms_methods_dump
bin=target/cmake/test/compiler
"$bin/ownership_test"
"$bin/types_test"
"$bin/recursion_test"
"$bin/ty_algebra_test"
"$bin/infer_test"
"$bin/implements_test"

status=0
"$oracle" > "$out/tables.rust"
"$bin/ms_check_dump" stdlib > "$out/tables.c"
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
"$bin/ms_check_dump" stdlib --scope $files > "$out/scope.c"
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
# Each line is keyed by file and function so that only the functions C claims are compared, with
# the diagnostics inside each (`diag L:C: message`): one Rust reports and C does not, or the
# reverse, is a difference.
# The Rust checker walks ownership only for a program that type checks, so it prints no ownership
# diagnostic in a file with another error; the oracle marks those files, and a diagnostic C reports
# there that Rust does not is an ownership one (C declines the functions that carry the error).
drop_unowned() {
    awk -v rust="$1" '
        BEGIN { while ((getline line < rust) > 0) {
            if (line ~ /^== /) file = substr(line, 4)
            else if (line == "ownership-skipped") skip[file] = 1
            else if (line ~ /^diag /) seen[file SUBSEP line] = 1 } }
        /^== / { file = substr($0, 4) }
        !((file in skip) && /^diag / && !((file SUBSEP $0) in seen)) { print }' "$2"
}
keyed() {
    awk '/^== / { file = $2; key = ""; next } /^(fn|const) / { key = file " " $2 } key != "" { print key "|" $0 }' "$1"
}
"$oracle" --bodies $files > "$out/bodies.rust"
"$bin/ms_check_dump" stdlib --bodies $files > "$out/bodies.c.all"
drop_unowned "$out/bodies.rust" "$out/bodies.c.all" > "$out/bodies.c"
keyed "$out/bodies.c" > "$out/bodies.c.raw"
# A function the ownership walk handed back is marked; Rust's ownership diagnostics inside it have no
# C twin yet, so a marked function that C reports nothing in is compared without Rust's diagnostics.
awk -F'|' '/\|(fn|const) .* ownership-declined$/ { print $1 }' "$out/bodies.c.raw" | sort -u > "$out/bodies.declined.all"
awk -F'|' '$2 ~ /^diag / { print $1 }' "$out/bodies.c.raw" | sort -u > "$out/bodies.c.diagnosed"
comm -23 "$out/bodies.declined.all" "$out/bodies.c.diagnosed" > "$out/bodies.declined"
sed 's/ ownership-declined$//' "$out/bodies.c.raw" > "$out/bodies.c.keyed"
cut -d'|' -f1 "$out/bodies.c.keyed" | sort -u > "$out/bodies.keys"
keyed "$out/bodies.rust" | awk -F'|' -v list="$out/bodies.keys" -v declined="$out/bodies.declined" '
    BEGIN { while ((getline line < list) > 0) keep[line] = 1; while ((getline line < declined) > 0) skip[line] = 1 }
    ($1 in keep) && !(($1 in skip) && $2 ~ /^diag /)' > "$out/bodies.rust.keyed"
# A call of a function another module exports is claimed; a change that declines it drops hundreds of
# functions, so one fixture pins it.
if ! grep -q 'body_imported_call.ms 3:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a call of an imported function is no longer checked in C (compiler/tests/scope/body_imported_call.ms)"
    status=1
fi
# A call that leaves out a parameter with a default, or passes a record, is claimed too.
if ! grep -q 'body_argument_kinds.ms 11:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a call with a record argument or an omitted default is no longer checked in C (compiler/tests/scope/body_argument_kinds.ms)"
    status=1
fi
# A number returned or passed where an Optional is expected, and `none`, are claimed (`some_wrap`).
if ! grep -q 'body_optional_wrap.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_optional_wrap.ms 4:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a value used as an Optional is no longer checked in C (compiler/tests/scope/body_optional_wrap.ms)"
    status=1
fi
# A record built with its defaults left out, and passed as an `ok` payload, is claimed.
if ! grep -q 'body_construct_defaults.ms 5:1$' "$out/bodies.keys" || ! grep -q 'body_construct_defaults.ms 8:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a record built with defaults is no longer checked in C (compiler/tests/scope/body_construct_defaults.ms)"
    status=1
fi
# A function over a type that closes is checked in C: the ownership pass knows it is a resource.
if ! grep -q 'body_resource_param.ms 11:1$' "$out/bodies.keys" || ! grep -q 'body_resource_param.ms 14:1$' "$out/bodies.keys" || ! grep -q 'body_resource_param.ms 18:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a function over a type that closes is no longer checked in C (compiler/tests/scope/body_resource_param.ms)"
    status=1
fi
# A lambda with a written result in a generic method row, a list of `MapEntry`, a `Set`, a function passed for a `var` callback and a plain value for `E?` are claimed.
if ! grep -q 'body_closure_methods.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_closure_methods.ms 4:1$' "$out/bodies.keys" || ! grep -q 'body_closure_methods.ms 8:1$' "$out/bodies.keys" || ! grep -q 'body_closure_methods.ms 15:1$' "$out/bodies.keys" || ! grep -q 'body_closure_methods.ms 18:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a closure method, a MapEntry list or a Set is no longer checked in C (compiler/tests/scope/body_closure_methods.ms)"
    status=1
fi
# A sized integer given where another type is expected, and the reverse, are reported in C.
if ! grep -q 'body_sized_mismatch.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_sized_mismatch.ms 4:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a sized integer used as another type is no longer checked in C (compiler/tests/scope/body_sized_mismatch.ms)"
    status=1
fi
# A number literal given for an Optional of a sized number takes that type and is wrapped.
if ! grep -q 'body_optional_sized.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_optional_sized.ms 10:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a literal given for an Optional sized number is no longer checked in C (compiler/tests/scope/body_optional_sized.ms)"
    status=1
fi
# `Void` as a type argument (`Result[Void, Error]`) is an annotation C accepts.
if ! grep -q 'body_void_argument.ms 1:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a Void type argument is no longer checked in C (compiler/tests/scope/body_void_argument.ms)"
    status=1
fi
# A value given for an instance of a generic interface (`Src[Int]`) that it fits by its methods is claimed.
if ! grep -q 'body_generic_interface_shape.ms 17:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a value for a generic interface instance is no longer checked in C (compiler/tests/scope/body_generic_interface_shape.ms)"
    status=1
fi
# The smallest Int (`-9223372036854775808`) is a literal of its own.
if ! grep -q 'body_int_minimum.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_int_minimum.ms 4:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: the smallest Int literal is no longer checked in C (compiler/tests/scope/body_int_minimum.ms)"
    status=1
fi
# `?` on an Optional in a function that returns one is checked in C.
if ! grep -q 'body_try_optional.ms 4:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: ? on an Optional is no longer checked in C (compiler/tests/scope/body_try_optional.ms)"
    status=1
fi
# A borrowing call on a text literal, used in place, is checked in C (ownership is left to Rust).
if ! grep -q 'body_literal_borrow.ms 1:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a borrowing call on a literal is no longer checked in C (compiler/tests/scope/body_literal_borrow.ms)"
    status=1
fi
# A method of a generic type names the receiver's variables (`held: T`) and its own in annotations.
if ! grep -q 'body_generic_method.ms 4:11$' "$out/bodies.keys" || ! grep -q 'body_generic_method.ms 8:11$' "$out/bodies.keys"; then
    echo "FAIL bodies: a method of a generic type is no longer checked in C (compiler/tests/scope/body_generic_method.ms)"
    status=1
fi
# A match that yields a value, with an arm that leaves (`return`), is checked in C.
if ! grep -q 'body_match_leaving_arm.ms 6:1$' "$out/bodies.keys" || ! grep -q 'body_match_leaving_arm.ms 15:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a match with a leaving arm is no longer checked in C (compiler/tests/scope/body_match_leaving_arm.ms)"
    status=1
fi
# An instance of a generic type given for an interface it fits by its generic methods is claimed.
if ! grep -q 'body_generic_receiver_interface.ms 17:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a generic type given for an interface is no longer checked in C (compiler/tests/scope/body_generic_receiver_interface.ms)"
    status=1
fi
# A type variable given where another type is expected, and the reverse, are reported in C.
if ! grep -q 'body_variable_mismatch.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_variable_mismatch.ms 4:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a type variable used as another type is no longer checked in C (compiler/tests/scope/body_variable_mismatch.ms)"
    status=1
fi
# A loop over a list whose element is a type variable is checked in C.
if ! grep -q 'body_for_variable_list.ms 1:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a loop over a list of a type variable is no longer checked in C (compiler/tests/scope/body_for_variable_list.ms)"
    status=1
fi
# A loop over a map or a set is checked in C (ownership and lowering leave it to Rust).
if ! grep -q 'body_for_collection.ms 1:1$' "$out/bodies.keys" || ! grep -q 'body_for_collection.ms 7:1$' "$out/bodies.keys"; then
    echo "FAIL bodies: a loop over a map or a set is no longer checked in C (compiler/tests/scope/body_for_collection.ms)"
    status=1
fi
if cmp -s "$out/bodies.rust.keyed" "$out/bodies.c.keyed" && [ -s "$out/bodies.c.keyed" ]; then
    echo "ok   bodies ($(wc -l < "$out/bodies.keys") functions, $(grep -c '|expr ' "$out/bodies.c.keyed") expressions)"
else
    echo "FAIL bodies: first difference"
    diff "$out/bodies.rust.keyed" "$out/bodies.c.keyed" | head -20 || true
    status=1
fi

# Project imports: an entry that imports project modules, checked through the C module graph
# (`--project`) against the Rust checker given the same import map. Export errors print as
# `import L:C: message`.
for entry in compiler/tests/project/main.ms compiler/tests/project/uses.ms; do
    name=$(basename "$entry" .ms)
    "$oracle" --project "$entry" > "$out/project-$name.rust"
    "$bin/ms_check_dump" stdlib --project "$entry" | sed 's/ ownership-declined$//' > "$out/project-$name.c"
    if cmp -s "$out/project-$name.rust" "$out/project-$name.c" && [ -s "$out/project-$name.c" ]; then
        echo "ok   project $name ($(grep -c '^import ' "$out/project-$name.c") import diagnostics)"
    else
        echo "FAIL project $name: first difference"
        diff "$out/project-$name.rust" "$out/project-$name.c" | head -20 || true
        status=1
    fi
done

# Ownership: the diagnostics inside each function the C passes checked, against the Rust checker's,
# on the ownership fixtures and the corpus. Only functions the C walk handles are compared.
ownership_files=$(find compiler/tests/ownership compiler/tests/scope tests/conformance/fixtures -name '*.ms' | sort)
"$oracle" --ownership $ownership_files > "$out/ownership.rust"
"$bin/ms_check_dump" stdlib --ownership $ownership_files > "$out/ownership.c.all"
drop_unowned "$out/ownership.rust" "$out/ownership.c.all" > "$out/ownership.c"
keyed "$out/ownership.c" > "$out/ownership.c.keyed"
cut -d'|' -f1 "$out/ownership.c.keyed" | sort -u > "$out/ownership.keys"
keyed "$out/ownership.rust" | awk -F'|' -v list="$out/ownership.keys" '
    BEGIN { while ((getline line < list) > 0) keep[line] = 1 }
    $1 in keep' > "$out/ownership.rust.keyed"
if cmp -s "$out/ownership.rust.keyed" "$out/ownership.c.keyed" && [ -s "$out/ownership.c.keyed" ]; then
    echo "ok   ownership ($(wc -l < "$out/ownership.keys") functions, $(grep -c '|diag ' "$out/ownership.c.keyed") diagnostics)"
else
    echo "FAIL ownership: first difference"
    diff "$out/ownership.rust.keyed" "$out/ownership.c.keyed" | head -20 || true
    status=1
fi

# Effect scan: the callables each function or constant the C checker checked references (first
# reference of each, in source order), against the Rust scan's. Only functions C claims are compared.
"$oracle" --effects $files > "$out/effects.rust"
"$bin/ms_check_dump" stdlib --effects $files > "$out/effects.c"
# The Rust checker scans effects only for a program it accepts; leave the others out.
awk '/^== / { file = $2 } /^unchecked$/ { print file }' "$out/effects.rust" > "$out/effects.unchecked"
for side in rust c; do
    awk -v list="$out/effects.unchecked" '
        BEGIN { while ((getline line < list) > 0) skip[line] = 1 }
        /^== / { dropped = ($2 in skip) }
        !dropped { print }' "$out/effects.$side" > "$out/effects.$side.kept"
    mv "$out/effects.$side.kept" "$out/effects.$side"
done
keyed "$out/effects.c" > "$out/effects.c.keyed"
cut -d'|' -f1 "$out/effects.c.keyed" | sort -u > "$out/effects.keys"
# A method has no symbol name: the Rust scan's serial method ids and the C scan's method nodes both read `method`.
sed -E 's/^edge [^ ]*method[0-9]+ /edge method /' "$out/effects.rust" > "$out/effects.rust.normal"
keyed "$out/effects.rust.normal" | awk -F'|' -v list="$out/effects.keys" '
    BEGIN { while ((getline line < list) > 0) keep[line] = 1 }
    $1 in keep' > "$out/effects.rust.keyed"
if cmp -s "$out/effects.rust.keyed" "$out/effects.c.keyed" && [ -s "$out/effects.c.keyed" ]; then
    echo "ok   effect scan ($(wc -l < "$out/effects.keys") functions, $(grep -c '|edge ' "$out/effects.c.keyed") references)"
else
    echo "FAIL effect scan: first difference"
    diff "$out/effects.rust.keyed" "$out/effects.c.keyed" | head -20 || true
    status=1
fi


# Effect directives on every source file, then generated graphs, each compared with the Rust result.
# The fixture is written here because the repository forbids carriage returns in stored files: it has CRLF
# and CR-only line ends, non-breaking and em spaces, empty names and directives without a separator.
printf '// ms: allow_effect std.fs.read\r\n//   ms:  allow_effect   db.*  \r\n\r\n\302\240// ms: effect a.b\342\200\203\n// ms: effect  \n// ms:effect x\n// ms: allow_effect\nfn f() {}\n\n// ms: allow_effect *\n\n// ms: effect z\r\r\nfn g() {}\n// plain\nlet x = 1' > "$out/directives-fixture.ms"
{ find . -name '*.ms' -not -path './target/*' -not -path './.git/*' | sort; echo "$out/directives-fixture.ms"; } > "$out/sources.txt"
xargs "$effects_oracle" directives < "$out/sources.txt" > "$out/directives.rust"
xargs "$bin/ms_effect_dump" directives < "$out/sources.txt" > "$out/directives.c"
if cmp -s "$out/directives.rust" "$out/directives.c"; then
    echo "ok   effect directives ($(grep -c '^file' "$out/directives.rust") files)"
else
    echo "FAIL effect directives: first difference"
    diff "$out/directives.rust" "$out/directives.c" | head -20 || true
    status=1
fi

# The corpus: every source file that writes a method, a property marker or an impl, plus a fixture for
# what no file does (a method on an interface, methods on types another module declares).
printf 'type Remote[T]:\n\tvalue: T\n\nenum Mode:\n\tFast\n\tSlow\n' > "$out/desugar-foreign.ms"
printf 'interface Shape:\n\tfn area() Int\n\nfn Shape.twice() Int:\n\treturn 2\n\nfn Remote[T].get() T:\n\treturn self.value\n\nfn Mode.label() String:\n\treturn "m"\n\nfn Remote.broken() Int:\n\treturn 1\n' > "$out/desugar-fixture.ms"
xargs grep -lE '^(var )?fn (move )?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\.|^impl |^// ms: (data|clonable)' < "$out/sources.txt" > "$out/desugar-sources.txt"
echo "$out/desugar-fixture.ms" >> "$out/desugar-sources.txt"
desugar_status=0
for mode in user std; do
    xargs "$desugar_oracle" "$mode" < "$out/desugar-sources.txt" > "$out/desugar-$mode.rust"
    xargs "$bin/ms_desugar_dump" "$mode" < "$out/desugar-sources.txt" > "$out/desugar-$mode.c"
    cmp -s "$out/desugar-$mode.rust" "$out/desugar-$mode.c" || desugar_status=1
done
"$desugar_oracle" foreign "$out/desugar-foreign.ms" "$out/desugar-fixture.ms" > "$out/desugar-foreign.rust"
"$bin/ms_desugar_dump" foreign "$out/desugar-foreign.ms" "$out/desugar-fixture.ms" > "$out/desugar-foreign.c"
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

# Every file that declares an interface, plus a fixture for what no file does: a repeated operation
# and a type parameter that shadows one.
printf 'interface Shape[T]:\n\tfn area() Int\n\tfn area() Int\n\tfn map[T]() T\n\tfn pair[U, U](other: Self) U\n\tfn nest(other: List[Self]) Int\n' > "$out/methods-fixture.ms"
xargs grep -lE '^interface |^(var )?fn (move )?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\.' < "$out/sources.txt" > "$out/methods-sources.txt"
echo "$out/methods-fixture.ms" >> "$out/methods-sources.txt"
xargs "$methods_oracle" < "$out/methods-sources.txt" > "$out/methods.rust"
xargs "$bin/ms_methods_dump" stdlib < "$out/methods-sources.txt" > "$out/methods.c"
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
    "$bin/effect_graph_gen" "$seed" > "$out/graph.txt"
    "$effects_oracle" graph < "$out/graph.txt" > "$out/graph.rust"
    "$bin/ms_effect_dump" graph < "$out/graph.txt" > "$out/graph.c"
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
