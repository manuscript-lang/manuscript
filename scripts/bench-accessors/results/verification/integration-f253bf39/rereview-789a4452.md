# Independent integration correction re-review

**APPROVE the correction.** The P2 blocker in the immutable merge review is resolved. No new finding was established in this exact four-file correction. This is an independent code-review judgment, not author self-approval, completion of the primary agent's remaining gates, or authorization to publish.

Exact reviewed commit: `789a4452816128fae9de7d1b515543897279abe7`.
Exact parent: `e9849d26218ce0361df86349956b1c11ad502d07`.
Fresh detached read-only checkout: `/workspace/manuscript-accessor-integration-fix-review`.
Original review: `/tmp/accessor-main-integration-review-e9849d26.md`.
HEAD and clean tracked status verified. No tracked files edited; temporary probes and overlays are confined to ignored `.artifacts/reviewer-789a4452`.

## Reviewed correction

Read the entire four-file diff (67 insertions, 18 deletions), current repository guidance and relevant compiler instructions/lesson. The original approved accessor contract and prior integration review remain the governing context.

`markCounted` now retains each callable declaration and invokes the common executable visitor with both `decl.Params` and `decl.Body`. This adds default-expression edges before the existing SCC computation. The change leaves the existing accessor-edge resolution, nested executable traversal, cycle marking, sampled Enter/Exit implementation, callee default evaluation, source positions, and callable eligibility intact. Both direct functions and source methods carry valid declarations from their established eligibility checks. No runtime admission policy or new per-call wrapper was introduced.

The emitted regression requires Enter/Exit in both members of the exact default/accessor cycle, so a partial fix that marks only the function or only the accessor is rejected. The native regression extends the existing depth/cancellation test with a finite 210000-step cycle. It observes both a Manuscript depth fault and the existing cancellation identity from a cancelled Execution. The finite case fails safely if the cycle loses all guards. The compiler lesson records the verified cause and routes future work to those regressions.

## Independent evidence

All commands used pinned Go `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, PATH with its bin directory first, `GOCACHE=/tmp/manuscript-accessor-go-cache`, `GOPATH=/tmp/manuscript-accessor-go`, `GOFLAGS=-buildvcs=false`, and `XDG_CACHE_HOME=/tmp/manuscript-accessor-cache`.

- `git diff --check HEAD^ HEAD`: PASS.
- `go test ./pkg/lower -run 'Accessor.*Cycles|PresenceAccessorsPreserveDirectLocalClosureResults|OmittedDefaults' -count=1`: PASS.
- `go test -overlay .artifacts/reviewer-789a4452/payload-overlay.json ./pkg/build -run '^TestAccessorFaultFramesAndRecursiveCancellation$' -count=1`: PASS (2.690s). The overlay supplies only the existing pinned `.build-payload.tar.gz` from `/workspace/manuscript-accessor-design`; this checkout otherwise lacks its Go embed input. Production Go source is unmodified.
- Independently ran the new emitted regression with only `pkg/lower/lower_recursion.go` overlaid back to e9849d26. EXPECTED FAIL, separately identifying missing depth accounting in `func call_` and `func method_`. This establishes that the new regression distinguishes the original defect.
- Recompiled and reran the original reviewer-owned finite default/accessor source with `Counter(210000)`. EXPECTED DEPTH FAULT: `call depth limit exceeded (200000 nested calls)`. Emitted code now has `rt.Enter(ctx)` and normal-return `rt.Exit(ctx)` in both `call_symbol3` and `method_32`. On e9849d26 the same source completed without a fault; on first parent f508ab6e it faulted.
- Recompiled and reran the ordinary-function equivalent from the original exact-main control. EXPECTED DEPTH FAULT at the correction. This preserves the original attribution: exact integrated main `f253bf399d0b60d27e2b5fe8af4ae085e56c6a98` allowed the same 210000-step ordinary-function/default cycle, so the cause was inherited from #507 rather than the accessor conflict resolution.
- Recompiled and reran the original reviewer positive integration probe: PASS, `1 tests, 0 failed`. It covers scalar capture snapshots and live collection aliases; direct closure Optional/Result presence reads and match consumers; captured Optional fallback; function-valued accessor defaults and explicit-argument bypass; accessor-before-failing-try ordering in a direct local closure; concrete, interface-view and generic-bound Error.message method calls through closures.

Probe source, emitted programs, binaries, the old-recursion red overlay and the payload overlay remain under `.artifacts/reviewer-789a4452`. Native reviewer programs were compiled using the exact correction's compiler and ordinary pinned Go builds against the exact correction runtime. The initial immutable review checkout and its original first-parent/main evidence remain unchanged.

## Limits

The code-review blocker is closed. The primary agent's applicable final correction suites and release gates remain separate requirements; I did not repeat broad verify/e2e/build, race/fuzz, benchmark, book/docs, extension/debugger or distribution checks. Linux/amd64 only. The focused native test directly exercises depth/cancellation and existing source-fault cases, but does not prove every recursion, cancellation or cleanup combination. The unrelated baseline CSV fuzz timeout remains outside this correction and no cause or flakiness claim is established here.

This judgment covers exactly `789a4452816128fae9de7d1b515543897279abe7` over its stated parent. Later changes need their own exact-diff review.
