# Independent bounded main #517 composition review

APPROVE final candidate `f97b511ea6978eb4e375df582819b788d8a6219a` over merge `0443f74c36d101575a6e964448d0d547f11c424a`, integrating main `d70b29bec4379ae1ba4d8d605cac93c8f89e192f` (#517) over published PR516 head `bc24cf9379f5320a0c41ba78392097e3f2d1b866`. The dynamic-filter fallback defect found during independent review is corrected. No remaining concrete blocker was established. This is an independent code-review judgment, not author self-approval or an action to publish/update/merge a PR.

Reviewed the complete bounded diff: incoming map/filter result storage and store helper, final private fallback correction, runtime/native regressions and durable runtime lesson. Reviewer source was exported directly from exact f97b511e with git archive into `/workspace/manuscript-accessor-review-main517`. Production files were not edited; reviewer probes/overlays/generated programs are confined to `.artifacts/reviewer-f97b511e`. The primary checkout remained clean at exact f97b511e when checked.

## Finding established and corrected

Original #517 filter constructed a typed result then called Append for each accepted input value. The existing NewList contract deliberately permits a primitive-labelled List to hold nonmatching dynamic payloads in boxed storage, as TestPrimitiveListConstructorsAndAliases already asserts. Prior filter passed selected values through NewList, preserving this fallback. Incoming filter instead panicked when a selected boxed payload failed the typed Append assertion. This is a runtime fallback compatibility regression; no ordinary checked-source reachability was claimed.

Independently demonstrated the identical reviewer-owned filter probe passing on prior production and failing with only exact original merge0443f74c library_algorithms/list_storage overlaid: `interface conversion: interface {} is string, not int64`. Inputs were a NewList labelled List[Int] containing an Int, String and nested Optional payload. The prior runtime production was byte-identical to bc24cf93, establishing attribution to incoming #517.

The final correction checks accepts only after a predicate accepts a value, converts current private output to boxed storage if needed, then appends the original Value. Rejected mismatches do not unnecessarily box an otherwise typed result. The factored boxStorage copies current values before clearing primitive backing, then store uses the same helper for map. Ordinary Append, public mutation semantics and accessor implementations are unchanged.

## Contract trace

Map keeps the captured original header/length and allocates fresh private storage of the result type. Each callback runs once in captured order; store retains earlier values across a primitive-to-boxed fallback, and later stores fill remaining slots. No partially initialized output escapes to callbacks or callers. Filter appends only accepted original Values, retaining order and shallow aliases; fallback changes only private output representation. Empty results remain mutable and expose normal outer Optional absence through first/last.

Both paths retain original per-element cancellation checks and the common marked/unmarked callback guards. Native wrapper delivery checks remain in place. Fault/cancellation stops traversal without returning partial output. No purity assumption, memoized read, source-call guard change or added callback cancellation sampling was introduced. Callback mutation retains captured Go-header semantics: writes to the captured backing remain visible, append does not extend traversal, and receiver accessor reads remain live.

List length/is_empty/first/last continue reading the authoritative returned List through its representation-aware accessors. First/last preserve Optional nesting and mutable payload identity; they do not copy/freeze elements. Result outer storage is fresh, while child references remain shared. Primitive typed results and boxed dynamic/Optional/record results use the same public read path. The earlier accessor classification, Error.message, lexical method cache and default-cycle corrections are untouched by this bounded change.

## Independent validation

Pinned SDK `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, bin first in PATH; GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS='-buildvcs=false -p=2', XDG_CACHE_HOME=/tmp/manuscript-accessor-cache throughout.

- `git diff --check bc24cf9379f5320a0c41ba78392097e3f2d1b866 f97b511ea6978eb4e375df582819b788d8a6219a`: PASS.
- `go test -race ./pkg/runtime -run 'TestListTransformResultsPreserveDynamicFallbackAndAccessorReads|TestPrimitiveListConstructorsAndAliases|TestListRangeNestedAndCallbackExits|TestListTraversalMatchesGoRange|TestCompiledForEachReentryAndCopiedCaptures' -count=1`: PASS, 1.210s. Includes all four primitive map/filter fallback cases and live accessor/fresh-storage assertions.
- `go test -race ./pkg/runtime -run '^TestListCallbackTraversalsUseCapturedBacking$' -count=1`: PASS, 1.017s. Existing mutation oracle covers map/filter and other callback traversals at two capacities.
- Extracted the new three-test Manuscript fixture, compiled it with exact candidate compiler, then executed emitted Go against exact candidate runtime: PASS, `3 tests, 0 failed`. Covers four primitive result types, post-result mutation/live endpoints/length, fresh outer storage, empty results, generic nested Optional payloads, mutable child aliases and callback mutation.
- `go test -race -overlay .artifacts/reviewer-f97b511e/probe-overlay.json ./pkg/runtime -run '^TestReviewerPrivateResultFallbackSelectionAndExits$' -count=1`: PASS, 1.017s. Reviewer-only test independently covers mismatches at first/middle/last positions and nil dynamic payload, checks map preserves exact boxed contents, checks filter remains typed when it rejects mismatches, and checks map/filter callback counts plus cancellation/fault/admission identity for both marked compiled and ordinary callbacks. Production source remains exact.
- `go test -overlay .artifacts/reviewer-f97b511e/original-merge-overlay.json ./pkg/runtime -run '^TestListTransformResultsPreserveDynamicFallbackAndAccessorReads$' -count=1`: EXPECTED FAIL after restoring only original0443f74c storage/algorithm files. New Int/filter regression panics on the nested Optional payload (`msruntime.Alternative, not int64`). This independently establishes that the committed regression rejects the original defect.

Read primary logs in `.artifacts/integration-main517`: full runtime race PASS26.971s; lower/compiler/nativeabi/stdlib pass; focused native e2e/build PASS31.555s/8.520s; verify completes; eight selected collection/Optional/error conformance fixtures PASS. These are primary results, not additional independently rerun broad suites.

## Limits

Linux/amd64 focused execution only. Tests establish the described composition and correction, not all possible callback interleavings or every external runtime embedding. The dynamic fallback counterexample intentionally exercises an existing runtime compatibility contract rather than claiming unchecked payloads arise in ordinary compiled source. No new benchmark or performance claim was made; previous benchmark records retain their own exact revision scope. No baseline chasing, primary source edits, publication, PR update or merge was performed by this reviewer. Later production changes require a new exact review.
