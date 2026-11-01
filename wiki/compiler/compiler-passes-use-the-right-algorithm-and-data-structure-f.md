[Wiki](../index.md) › [Compiler and build](index.md)

# Compiler passes use the right algorithm and data structure for their input size

Decision: the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases. A pass that re-walks a shared graph per root, scans a list per lookup, or allocates per-byte tables is a defect even when small inputs hide it.

Verified: type-suffix sugar must move the accumulated syntax tree into each wrapper. Cloning it for every `?` or `!` copies all preceding wrappers and makes construction quadratic; preserve node IDs and positions while removing the discarded copies.
Evidence: [suffix parser](../../crates/ms-syntax/src/parser.rs), [shape and position regressions](../../crates/ms-syntax/tests/type_suffix.rs), [interleaved parser measurements](../../bench/perf/parser-suffix/README.md).

Verified: replaying failed type-argument speculation must preserve the token cursor, final nesting depth, consumed node IDs and diagnostic; include starting depth in the key so a nesting-limit failure is not treated as an unconditional grammar failure. Record only nested, retry-eligible failures, and measure shallow indexing: unconditional cache work can erase gains on ordinary input.
Evidence: [speculative parser](../../crates/ms-syntax/src/parser.rs), [metadata regressions](../../crates/ms-syntax/tests/bracket_speculation.rs), [accepted and rejected measurements](../../bench/perf/parser-speculation/README.md).

Verified: repeatedly recomputing use counts and scanning a function to delete the last unused instruction makes dead-expression chains quadratic. Decrement operand use counts as dead users are removed, and visit newly dead definitions with a worklist. Preserve faulting instructions and owned results as roots.

Verified: LLVM's SLP vectorizer (in `opt`) and machine scheduler (in `llc`) are quadratic in the length of one function, so a 20000-element list literal built in 127s in Release against 0.4s in Cranelift. A function body over 12000 IR lines turns both off for the module; loop vectorization stays on. Time Release builds, not only Debug, at N/2N/4N, and read `opt -time-passes` and `llc -time-passes` before blaming the frontend.
Evidence: [LLVM invocation](../../crates/ms-clif/src/llvm_obj.rs), [large literal regression](../../crates/ms-cli/tests/llvm.rs).

Apply when: adding or changing a lexer, parser, checker, or lowering pass, or a cache or table they share.
Evidence: [type recursion pass](../../crates/ms-check/src/recursion.rs), issues #490 and #491.
Evidence: [method registration and lookup](../../crates/ms-check/src/contracts.rs), [candidate regressions](../../crates/ms-check/src/method_candidates_tests.rs), [editor queries](../../crates/ms-check/src/editor.rs).
Evidence: [inliner](../../crates/ms-mir/src/opt/inline.rs), [constant-bonus regression](../../crates/ms-mir/tests/opt_inline.rs).
Evidence: [dead-code elimination](../../crates/ms-mir/src/opt/simplify.rs), [dead-graph and unused-check regressions](../../crates/ms-mir/tests/opt_simplify.rs).
Evidence: [lending accessors](../../tests/e2e/testdata/stdlib/json-accessors.ms), [lent results](../tests/e2e/testdata/accept/ref-lend-results.ms), [ownership corpus](../crates/ms-check/tests/ownership/accept/ref_some_payload.ms), `json.navigate` in [the stdlib bench](../../bench/perf/stdlib/json_bench.ms) (351 to 56 ns per three nested reads).
Evidence: [generic recursion validation](../../crates/ms-check/src/recursion.rs), [finite DAG and ancestor-context regressions](../../crates/ms-check/tests/generic_recursion.rs), [cycle-prefix and differential regressions](../../crates/ms-check/src/recursion/tests.rs).
Verify: generate inputs at N, 2N, 4N (chained declarations, long function bodies, many matches, deeply nested literals), time `ms check` and `ms build` separately, and profile any step that grows faster than 2x per doubling. Prefer a global memo or index over a per-query rescan, and keep cycle checks ahead of memo hits.
Verify: the frontend-only candidate tests check constant-size buckets for unrelated methods, generic bounds, overlapping implementations, module-local extensions, ambiguity order and editor members.
Verify: compare optimized MIR and native binaries before/after on real programs, and measure the entire build as well as the inline pass at N/2N/4N. A compiler-only improvement does not imply faster generated programs.
Verify: simplify unused arithmetic chains at N/2N/4N; shared operands disappear without deleting an unused overflow check.
Verify: `ms test tests/e2e/testdata/stdlib/json-accessors.ms --build-type Release` with the debug `ms` (MIR verified after every pass) passes.
Verify: forty-level branching prefixes and distinct diamond arms into preserving cycles check without expanding every path; direct and mutual cycles, changed arguments, acyclic tails, and same-spelled declarations in different modules keep their diagnostics.
