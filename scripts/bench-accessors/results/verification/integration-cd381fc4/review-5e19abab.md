# Independent bounded main #520 composition review

APPROVE exact merge `5e19ababf5cb59a65fc000a78f5b46cc38c55283`, integrating main `cd381fc4570dcd5d2763ce6c3eb0ef5619238cda` (#520) over published parent `2e29c5ccf6e98681d9d520164f120aad5b78fcba`. No concrete blocker was established. This is an independent exact-code review, not author self-approval, publication or a PR merge action.

Reviewed the complete three-file first-parent diff and fixture migration against incoming main. Exact source was exported with git archive into `/workspace/manuscript-accessor-review-main520`; reviewer probes/generated programs are under `.artifacts/reviewer-5e19abab`. No primary files or production source were edited. Independently checked no pkg/internal/tests edits after the candidate; later primary edits are evidence/documentation only.

## Composition and invariants

The six incoming length() reads are migrated to the approved length accessor; receivers and assertions are unchanged. No authored production changes accompany incoming main's literal optimization.

The new route selects checked primitive element identities after the established debug/large-literal routes have declined. Nominal, Optional, reference and unresolved generic element types retain their boxed/value path. OwnInt/Float/Bool/StringList each adopt a typed slice literal allocated for that evaluation; the source cannot observe or retain that private backing before the List is returned. Distinct evaluations have distinct mutable outer storage, while ordinary List aliases still point to the same authoritative handle. Empty slices remain safely mutable. Existing copying constructors, literal tables and large/debug fallback routes retain their own ownership contracts.

scalarSiblings preserves siblings' ordering rule: a nonconstant earlier operand is sequenced before a later match that can assign its local. Calls/getters retain source order in the Go literal. scalar lowers the same source expression once and changes only its scalar ABI, so source/native accessor invocations, source guards and native cancellation checks remain in their established bodies. No memoization, purity assumption or accessor-result cache is added. The try-hoisting scan still treats accessors as execution barriers; failure cannot skip a preceding getter or evaluate a subsequent element.

The Own helpers, like prior NewList construction, introduce no cancellation checkpoint of their own; surrounding call/accessor/loop semantics remain unchanged. A failed element does not expose a partially built List. Float negation continues through existing lowering, retaining negative zero. Nonprimitive literals retain nested Optional presence and mutable payload aliases. The reviewed #517 private transform boxing fallback and #518/#519 dispatch/representation corrections are untouched; no existing runtime method body is modified by the added Own helpers.

## Independent focused evidence

Pinned `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, bin first in PATH; GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS='-buildvcs=false -p=2', XDG_CACHE_HOME=/tmp/manuscript-accessor-cache throughout.

- `git diff --check 2e29 5e19abab`: PASS.
- Independently extracted/compiled the migrated incoming literal fixture and executed emitted Go against exact runtime: PASS, `1 tests, 0 failed`.
- Independently authored/compiled/executed composition.ms in ordinary compiler mode: PASS, `3 tests, 0 failed`. It exercises all four Own scalar list kinds, getter side effects and local snapshots before later match reassignment, direct and interface source getter results, failing/successful try within a primitive literal, repeated fresh construction and subsequent mutation/live endpoints, nested List reference aliases, generic boxed literal aliases, nested Optional.none and Float negative-zero sign.
- Recompiled the same three-test probe using CompileFileForBuild(..., compiler.Debug), then executed its emitted Go: PASS, `3 tests, 0 failed`.
- Examined emitted code: all four Own helpers are used; dynamic source getters remain ReadAccessor calls with scalar recovery, the concrete getter remains its direct source body, earlier local reads are wrapped in Seq before later matches, and the failing/successful try remains between its two getter occurrences. Failure observes exactly the preceding getter; success observes both in order.
- `go test ./pkg/lower -run 'TestAccessorReadPreventsTryHoisting|TestCoreAccessorsUseTypedReceiverOnlyHelpers|TestLargeListThreshold|TestLargeConstantListsLowerToTypedTables' -count=1`: PASS, 0.074s.
- `go test -race ./pkg/runtime -run '^TestListTransformResultsPreserveDynamicFallbackAndAccessorReads$' -count=1`: PASS, 1.016s. The earlier dynamic boxed-fallback/live accessor regression remains green.

Read primary completed logs in `.artifacts/integration-main520`: full lower/compiler PASS0.351s/2.585s; focused runtime race PASS1.839s; focused native e2e/build PASS40.751s/23.982s, including the new literal fixture and accessor/generic/struct/List cases; make verify completes with source documentation, tooling/LSP, examples and licenses. These are primary results, not independently duplicated broad suites.

## Limits

Linux/amd64 focused execution only. No redesign, new benchmark, performance claim or unrelated baseline integration. Earlier measurements retain their exact historical revision scope. These checks establish the stated literal/accessor composition rather than every expression or scheduling combination. No primary source edits, push, publication, PR update or merge performed by this reviewer. Later production changes require their own exact review; equivalent fixture-only getter migrations remain separately authorized by the user.
