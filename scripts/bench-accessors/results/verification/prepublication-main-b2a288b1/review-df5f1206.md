# Independent exact pre-publication integration review

APPROVE exact merge `df5f1206e7e6231e861a913d41ca78448a26fa86` over preserved first parent `3d3ba796559f165bf2c6a81c91b03608745d6db3`, integrating main `b2a288b19bb7acce05165d94b98b4a5c519bb09f` (#513–#515). No concrete blocker was established. This is an independent code-review judgment, not author self-approval or a publication/merge action. The user has authorized the primary agent to push normally and open a draft PR; this reviewer performed neither.

Immutable detached review checkout: `/workspace/manuscript-accessor-review-main515`; exact HEAD and clean tracked status verified. Probes and overlays are confined to ignored `.artifacts/reviewer-df5f1206`. No tracked source changed.

## Review scope and composition

Read the complete 12-file first-parent integration diff and the relevant main-to-merge composition in lowering, method dispatch and recursion. Applied current repository guidance and the established compiler/runtime/accessor contracts and expert lessons. Reviewed incoming callback buffer reuse, String parse/byte helpers, standard-contract lowering/operation caching, migrated fixtures and the new accessor integration regression.

Accessor exclusion now occurs before attempting the standard contract fast path and remains independently explicit in standardContractCall. Reads continue through direct accessor helpers or ReadAccessor; ordinary methods, including Error.message implementations, stay callable methods. The earlier 1ff193c0 scope-aware MethodSite lookup/demotion and nonempty argument-scope exclusion remain intact. Default-expression cycle analysis, direct-constructor counting, native accessor helpers and their path-specific cancellation checks are unchanged by this merge.

CallOperation only caches operations for native pointer receivers, matching actual receiver identity; each cache entry publishes a complete immutable receiver/function pair atomically. Source implementations continue through Bind, retaining each View's lexical scope, rather than acquiring a receiver-type-only cached target. Replacing a selected service does not reuse another pointer's operation. Method name and contract remain static per generated site. Cached operations still execute the original Function.Body, preserving admission/delivery cancellation, acquisition disposal, native live-state/resource gates and source behavior. The native Operation implementations examined build their guarded callable rather than snapshotting the operated state at binding.

Callback reuse retains the existing proof boundary: only compiled functions marked BorrowedArguments with exact labels borrow a per-invocation buffer; other functions retain Invoke. The new three-argument variant follows the existing one/two-argument guard path. Collection traversal, equality/hash evidence, payload aliases and comparator selection remain unchanged, and recursive library invocations own separate callback state. StringParseInt/ToBytes factor the existing algorithms without changing their output shape, ASCII/sign/overflow rules or byte-copy semantics.

## Source-marker correction

Incoming main standardContractCall built a bound callee solely to ask methodDefaults about eligibility, discarded it, then lowered the receiver again for the emitted operation. A nested receiver callable registered source markers in the discarded tree and triggered the printer's exact-once invariant.

Removing that throwaway lowering is correct: the preceding checks require all parameters supplied in declaration order. nativeDefaultParameters therefore marks every default present and returns the input callable unchanged; no default expression needs preparation on an eligible call. Calls with omitted or reordered arguments still take ordinary dispatch. The corrected eligibility path performs no receiver/argument lowering until eligibility is settled, then emits each exactly once. It preserves the source-marker assertion rather than suppressing it.

The new regression exercises a nested callable in a direct Clock receiver and a live accessor receiver that switches native/source/native Clock values through one observe site. It rejects repeated accessor reads and confirms ordinary native execution.

## Independent evidence

Environment: pinned `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, same bin first in PATH; GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS='-buildvcs=false -p=2', XDG_CACHE_HOME=/tmp/manuscript-accessor-cache.

- `git diff --check 3d3ba796 HEAD`: PASS.
- Independently ran the primary's minimal nested-Clock receiver compiler probe using exact df5f1206: diagnostics empty, Success true.
- Reran that identical probe with only lower_calls.go overlaid to exact incoming main b2a288b1: EXPECTED compiler failure, `lost generated source directives: printed 8 of 10`. This directly establishes that the correction distinguishes the inherited main defect.
- Independently extracted/compiled the new accessor-contract regression through exact merge compiler, then ran the emitted Go against exact merge runtime: PASS, `1 tests, 0 failed`. Generated observe contains one ReadAccessor nested as CallOperation's receiver, rather than a bound callable or duplicated receiver read.
- Independently compiled and executed a four-module standard Error probe: same concrete Reader type has module-local Error.message implementations returning different strings; one exported invoke(view: Error) site alternates left/right/left views. PASS, exit 0. Emitted invoke uses CallOperation, establishing that the new standard-contract path retains lexical source evidence and ordinary Error.message calls.
- `go test -race -overlay .artifacts/reviewer-df5f1206/operation-overlay.json ./pkg/runtime -run '^TestReviewerOperationCacheIdentityAndGuards$' -count=1`: PASS (1.129s). Reviewer-only test checks operation reuse for one native pointer, replacement by another same-type native pointer, concurrent alternating receivers at one site, cancellation through a populated cache and a changed live native closed-state guard. Production source is exact; only test source is overlaid.
- `go test ./pkg/lower -run 'TestDefaultAccessorCyclesKeepSampledDepthChecks|TestAccessorCyclesKeepSampledDepthChecks|TestInterfaceViewLowersReceiverOnce|TestCoreAccessorsUseTypedReceiverOnlyHelpers' -count=1`: PASS (0.438s).

Read the primary's affected-check logs: lower/compiler/checker/runtime/nativeabi/stdlib suites all pass; focused e2e and build checks pass (35.385s and 21.580s). Those are primary results, not represented as independent broad reruns.

## Limits

Linux/amd64 focused execution only. Prior review/measurement reports retain their own exact commit identities; the earlier 800547bb performance results are not freshly measured at df5f1206. This review does not claim exhaustive validation of every standard service, callback, platform or scheduling interleaving. The primary agent owns remaining applicable checks and the explicitly authorized normal push/draft PR. No merge is authorized or performed here. Subsequent production changes need their own exact review.
