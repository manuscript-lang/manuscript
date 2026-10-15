# Independent exact correction re-review

APPROVE the correction. The P1 blocker reported for immutable merge 8b4dd16f is resolved in exactly `1ff193c04a90965b969678f3a253c33220ca3edf` over parent `8b4dd16f43b528ef8ad339460c6ceeb4ef5a4110`. No new concrete finding was established in this seven-file correction. This is an independent code-review judgment, not author self-approval, completion of the primary agent's remaining verification matrix, or publication authorization.

Read-only detached review checkout: `/workspace/manuscript-accessor-review-scope`. Exact HEAD and clean tracked status verified. Original immutable report: `/tmp/accessor-512-review-8b4dd16f.md`. All reviewer probes, overlays, generated programs and controls are under ignored `.artifacts/reviewer-1ff193c0`; no tracked source changed.

## Correction and contract trace

Reviewed the complete seven-file diff against the original report, approved accessor semantics, current repository instructions and compiler/runtime expert guidance. Both MethodSite slots now match concrete receiver type, lexical module and registration generation. Slot demotion distinguishes different modules as well as receiver types, so alternating implementations with the same concrete type remain independently reusable. Entries hold immutable receiver-independent function targets, not bound receiver values. Concurrent cache insertions may reduce cache hit rates but cannot yield a mismatched module/type target: lookups validate each independently published atomic pointer.

CallMethod excludes every scope with argument scopes before lookup, retaining the existing slow path's specialization handling. A previously cached no-argument entry therefore cannot bypass argument scope evidence. Registration generation checks remain in both slots; the patch neither changes registry initialization assumptions nor introduces concurrent Register support. Static contract/name remain fixed per generated site. CallInterface continues to recover each explicit View's receiver and scope before lookup. Accessor dispatch remains on its existing separate path and retains its own scope evidence.

The new runtime regression alternates three module-local implementations of one concrete receiver and then calls two of them concurrently at one site. The source fixture extends the existing cross-module accessor scenario with a nongeneric Observed interface containing both a method and accessor. Its exported invoke_observed function supplies one method site used by both local views, and the fixture alternates them while retaining live accessor reads. The compiler lesson records the demonstrated failure and routes subsequent dispatch work to these checks.

## Independent evidence

Pinned environment throughout: `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, with its bin first in PATH; `GOCACHE=/tmp/manuscript-accessor-go-cache`, `GOPATH=/tmp/manuscript-accessor-go`, `GOFLAGS=-buildvcs=false`, `XDG_CACHE_HOME=/tmp/manuscript-accessor-cache`.

- `git diff --check 8b4dd16f HEAD`: PASS.
- `go test -race ./pkg/runtime -run 'TestInterfaceMethodSiteRetainsLexicalViewScope|TestMethodSiteFollowsReceiverTypeAndRegistration' -count=1`: PASS (runtime 1.109s).
- Recompiled the original independent four-module same-call-site Read/Reader source using the exact correction's compiler, then `go run .artifacts/reviewer-1ff193c0/scope_generated.go` against the exact correction runtime: PASS, exit 0. That identical source failed with exit 2 at both 8b4dd16f and exact integrated main 9dcc0bae, and passed on the first-parent control in the original review.
- `go test -race -overlay .artifacts/reviewer-1ff193c0/probe-overlay.json ./pkg/runtime -run '^TestReviewerScopeArgsBypassAndGeneration$' -count=1`: PASS (runtime 1.060s). Reviewer-only test first populates a direct cache entry, then gives the same site/type/module a nonempty Args scope and observes its Build path, verifies registration invalidates lookup, and verifies the site can resolve again afterward. Only test source is overlaid; production source remains exact.
- `go test -overlay .artifacts/reviewer-1ff193c0/red-overlay.json ./pkg/runtime -run '^TestInterfaceMethodSiteRetainsLexicalViewScope$' -count=1`: EXPECTED FAIL, `view 1 read 1`. This independently restores only exact pre-correction methods.go and proves the newly committed regression rejects the original defect.
- Independently compiled `tests/e2e/testdata/projects/accessors/main.ms` with Tests enabled through the exact correction compiler and ran the resulting Go against the exact correction runtime: PASS, `1 tests, 0 failed`. This covers the new mixed method/accessor module-local view composition in addition to the fixture's existing live reads, captured closures, generic forwarding and repeated views.

## Limits and remaining work

No broad suites duplicated: the primary agent owns final build/e2e/verification, resource/cancellation, documentation, packaging and other applicable gates. Native reviewer programs used the normal emitted Go linked to the exact runtime; the checkout's missing embedded build payload was not needed for these probes. Linux/amd64 only. The narrow race run covers concurrent method cache use after registration, not unsupported concurrent registry mutation. Benchmark protocol remains accepted; the exact contention harness and measurements require separate review. No push, PR, publication or merge performed.
