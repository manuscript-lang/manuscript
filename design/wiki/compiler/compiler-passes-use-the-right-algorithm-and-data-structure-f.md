[Wiki](../index.md) › [Compiler and build](index.md)

# Compiler passes use the right algorithm and data structure for their input size

Decision: the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases. A pass that re-walks a shared graph per root, scans a list per lookup, or allocates per-byte tables is a defect even when small inputs hide it.

Verified: module-loader input tracking must not scan all previously recorded paths for every module or embedded asset. Keep ordered output and membership separate within a load, seed membership from manifest lookups, and retain failed-input tracking as well as successful modules. Embedding the project root overlaps the manifest, entry and imported files; the loader regression checks their first-seen order without duplicates. Measure broad graphs and small controls, since the membership index stores another copy of each distinct path.
Evidence: input ordering regression, [paired module-loader measurements](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/module-inputs/README.md).

Verified: type-suffix sugar must move the accumulated syntax tree into each wrapper. Cloning it for every `?` or `!` copies all preceding wrappers and makes construction quadratic; preserve node IDs and positions while removing the discarded copies.
Evidence: suffix parser, shape and position regressions, [interleaved parser measurements](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/parser-suffix/README.md).

Verified: interpolation positions must advance through each literal prefix once. Recomputing the line and byte position from the start of the text for every interpolation token makes both long expressions and many short interpolations quadratic, especially in multiline text. The lexer rejects physical newlines inside expressions, so their token positions are relative byte offsets from one computed origin. Preserve nested/error attribution and LF/CRLF behavior when changing that mapping.
Evidence: interpolation position regressions.

Verified (2026-11-02): the failed-type-argument replay cache was deleted. One pass over the tokens sets a bit per `[` whose content has only type tokens; other brackets are indexes and never speculate (nested ones fail at once). Deep indexing is faster than with the cache (256 levels 84 to 49 µs) and ordinary input is unchanged. Removing the lexer's string-end table instead made nested interpolation 8x slower (256 levels 83 to ~700 µs): it is the precomputed output of the single lex pass, not a replay, so it stays.
Evidence: speculative parser, metadata regressions, [accepted and rejected measurements](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/parser-speculation/README.md).

Verified: repeatedly recomputing use counts and scanning a function to delete the last unused instruction makes dead-expression chains quadratic. Decrement operand use counts as dead users are removed, and visit newly dead definitions with a worklist. Preserve faulting instructions and owned results as roots.

Verified: probing a source method and then resolving its member again checks the same receiver twice; nested source calls compound that work exponentially. Retain a successful unique nongeneric source resolution, including its member scope and receiver control-flow facts. Keep diagnostic-producing receivers on the original recovery path so cascaded diagnostics retain their order. Count callback checks in a deterministic regression, and measure ordinary native/flat controls and complete Release builds alongside the chain.
Evidence: call candidate regressions, [source-call execution tests](../../../tests/lang/misc/source-call-resolution.ms), [reproduction drivers](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/call-candidates/README.md).

Verified: LLVM's SLP vectorizer (in `opt`) and machine scheduler (in `llc`) are quadratic in the length of one function, so a 20000-element list literal built in 127s in Release (Rust era, against 0.4s in Cranelift). Debug builds run with vectorization off (`vectorize = !debug`, `src/cli/pipeline.c`); in Release, keep functions from growing with the input (see the literal-chunk rule below). Time Release builds, not only Debug, at N/2N/4N, and read `opt -time-passes` and `llc -time-passes` before blaming the frontend.
Count definition lines rather than trailing metadata. Keep quoted metadata fields on one physical line with LLVM byte escapes: literal line breaks in a filename or scope name can otherwise manufacture apparent `define` or closing-brace lines for a textual size heuristic.
Verified: an LLVM `br` on a compare widened to `i8` (`zext`, then `icmp ne 0`) made InstCombine 8x slower on an 8000-arm `if n == k { return }` chain (15s to 2s), and a leftover unused `zext` blocked SimplifyCFG from turning the chain into a switch. Branch and select conditions use the `i1` directly; only values with a data use are widened.
Evidence: LLVM invocation, large literal regression, i1 condition test.

Verified: a `list.lit` over every element keeps all of them live, and register allocation is quadratic in the live set at each block (40000 runtime elements: 20s in Debug, Cranelift era). A literal over 512 plain-value elements is built from 256-element chunks joined with `msrt_list_concat`, 1s. Pushing each element instead made the LLVM IR 18x larger and Release 5x slower, so measure both profiles.
Evidence: long literal lowering, Debug build-time regression.

Verified: nominal ownership classification tracks active declaration identities and generic arguments, never display strings. Equal spellings from separate modules can hide nested resources if treated as a cycle; formatting shared phantom arguments can expand exponentially even when the actual fields are small. Keep ancestry local to the query, the existing depth cutoff and Closeable-first rule, and exercise checked multi-module cleanup as well as recursive and shared-DAG controls. Composite closer caches must likewise use the qualified lowering key: a display-name key reuses a helper with the wrong nominal MIR parameter type.
Collect `Closeable` and native `clone` facts (and `Decimal`'s plain-words status) in one method pass, preserving resource priority and native-only `Copy` behavior. Resolve the `clone` symbol lazily once, only when a named native method needs comparison. Borrow variable bounds directly for builtin-only read predicates; keep occurrence snapshots in `Type::clone` and `sub`, and release query borrows before returning. Build generic case bindings only when actual payload fields need substitution. An unused map does no validation or bound snapshotting; every actual payload still calls `sub` separately, after record-field classification, including payloads following empty cases.
Walk owning native collection argument chains iteratively. Keep every node’s declared-resource and plain-words checks, root `Copy` versus held `Move`, value-only Map traversal, and unchanged nominal ancestry and depth.
Completed child classifications may be reused for pointer-identical record fields within the same nominal frame, after every field has received its own substitution. Keep the first child alive through that frame, preserve its exact ancestor chain and depth, and continue visiting other fields after a resource result. Never carry this fact into another frame, substituted case payload, or public query.
Evidence: classification regressions, [native cleanup fixture](../../../tests/lang/projects/nominal_cycle_identity/conformance_test.ms).

Verified: shared type DAGs need query-local deduplication in equality and negative searches; create the hash table only after bounded ordinary work, and keep allocation-free small controls. Equality may reuse completed successful pairs, never active pairs or an unrestricted pointer shortcut: incomplete callable results retain their existing comparison behavior. A negative omission-permission preflight can preserve the root directly; a positive preflight must use the original recursive mapper so changed variable occurrences retain independent snapshots. Predicates must stay stable within each query. Inference-resolution searches need the same bounded traversal across arguments, parameters and results; retain the root rejection fast path and the distinction between invalid markers and unresolved inference variables. Ownership searches for promises use argument edges only and the defining module identity; preserve those decisions while deduplicating shared arguments.
Evidence: shared graph and metadata regressions.

Argument matching commits trial bindings only after a successful match. Build the
substituted pattern for widening and diagnostics only after matching fails; a
successful match does not use it. Keep partial-prefix failure and Optional retry,
widening and plain-value controls. Combining independently bounded inference
searches also needs unshared-forest measurements: a shared-root win can introduce
hashing for ordinary independent children.
Evidence: inference regressions,
[inference benchmark harness](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/checker-inference-resolution/README.md).

Verified: type interning deduplicates completed input nodes within each `intern` or `shape` query, preserving first representatives, flags and child order. Reuse empty memo storage, never answers across queries. Bypass recursive frames for leaves and leave short leaf-only rows uncached; cache wide rows too so shallow fanout cannot become quadratic.
Evidence: type identity regressions.

Verified: last-use pending drops are grouped by instruction anchor when recorded, not rediscovered by scanning every pending drop in the block for each insertion. Preserve ordinal order within each anchor: an owner may follow a family member's already-pending drop. Group iteration order must not affect placement; emit anchors in original instruction order. Allocate block tables lazily and keep the first anchor group inline: most blocks have at most one group, so indexing every such group adds avoidable allocation and hashing. Measure multi-block controls alongside the long-block win.
Evidence: pending-drop ordering and single-block regressions, #2940.

Verified: effect propagation's worklist does not bound diagnostic path reconstruction.
Many roots sharing one wide hub can repeat quadratic BFS work while producing only
linear path-label output. Share shortest suffixes only after individual searches
spend a graph-sized budget, so sparse direct violations avoid a full-graph pass.
Preserve stable equal-label ties and exclude a declaring start as its own terminal.
Evidence: effect path regressions,
[paired release checks and controls](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/effect-reachability/README.md).

Apply when: adding or changing a lexer, parser, checker, or lowering pass, or a cache or table they share.
Evidence: type recursion pass, issues #490 and #491.
Evidence: method registration and lookup, candidate regressions, editor queries.
Evidence: inliner, constant-bonus regression.
Evidence: dead-code elimination, dead-graph and unused-check regressions.
Evidence: [borrow-returning accessor](../../../tests/lang/stdlib/json-accessors.ms), borrowed results, ownership corpus, `json.navigate` in [the stdlib bench](../../../bench/perf/stdlib/json_bench.ms) (351 to 56 ns per three nested reads).
Evidence: generic recursion validation, finite DAG and ancestor-context regressions, cycle-prefix and differential regressions.
Verify: generate inputs at N, 2N, 4N (chained declarations, long function bodies, many matches, deeply nested literals), time `ms check` and `ms build` separately, and profile any step that grows faster than 2x per doubling. Prefer a global memo or index over a per-query rescan, and keep cycle checks ahead of memo hits.
Verify: the frontend-only candidate tests check constant-size buckets for unrelated methods, generic bounds, overlapping implementations, module-local extensions, ambiguity order and editor members.
Verify: compare optimized MIR and native binaries before/after on real programs, and measure the entire build as well as the inline pass at N/2N/4N. A compiler-only improvement does not imply faster generated programs.
Verify: simplify unused arithmetic chains at N/2N/4N; shared operands disappear without deleting an unused overflow check.
Verify: `ms test tests/lang/stdlib/json-accessors.ms --build-type Release` with the debug `ms` (MIR verified after every pass) passes.
Verify: forty-level branching prefixes and distinct diamond arms into preserving cycles check without expanding every path; direct and mutual cycles, changed arguments, acyclic tails, and same-spelled declarations in different modules keep their diagnostics.

Verified (2026-11-18, fuzzing with generated long functions): 20000 `m.add(k, v)` statements took 8s to lower and 114s in Release. `FuncBuilder` answered "what defines this value" by scanning every instruction of the function, once per statement, and the LLVM emitter's `slot_alias` rescanned the function for each `Slot`. The builder now keeps a `def_site` index (confirmed on lookup, since a rolled-back run or removed parameter leaves a stale entry), and the emitter finds all slot aliases in one pass per function (`slot_aliases`); 20000 statements now take 0.8s to lower and 8s in Release. Any new "find the definition of v" helper must use the index. `tools/scaling-check.ms` has `map_adds` and `release_map_adds` shapes. A generated long function is the quickest way to find this class: ask what each statement costs at N and 4N, in `emit` and in a Release build.
