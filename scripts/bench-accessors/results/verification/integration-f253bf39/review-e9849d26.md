# Independent integration review: e9849d26

Decision: **REQUEST CHANGES**. One P2 correctness blocker is proven. This is an independent review of an immutable merge, not author self-approval or authorization to publish.

Exact merge: `e9849d26218ce0361df86349956b1c11ad502d07`.
First parent: `f508ab6ea2f9adb2eb26895643429e5d39a3a935`.
Newly integrated main: `f253bf399d0b60d27e2b5fe8af4ae085e56c6a98` (#507 direct omitted defaults, #508 direct local closures).
Read-only checkout: `/workspace/manuscript-accessor-integration-review`. HEAD and clean tracked status verified before and after review. Only ignored reviewer artifacts were created under `.artifacts/reviewer-e9849d26`; no tracked files were edited.

## Proven finding

### P2: Default-bearing direct functions can omit recursion depth and cancellation accounting

Changed location: `pkg/lower/lower_direct.go:54–64`, particularly the unconditional addition to `g.direct` at line 64. Related unchanged omission: `pkg/lower/lower_recursion.go:21–27,61`, where cycle nodes retain only declaration bodies and visit them using `Callable(nil, n.body)`.

#507 admits functions with expression defaults into direct lowering. Their defaults run in the callee, but `markCounted` does not visit those defaults. A recursive edge expressed in a default is consequently absent from the direct-call graph. A cycle composed of a default and a concrete source accessor can therefore contain no `rt.Enter`/`rt.Exit` calls. This removes the required depth guard and sampled cancellation polling; unbounded recursion can continue until a Go stack failure rather than a Manuscript fault.

Minimal source (the actual retained probe additionally contains a finite 210000-iteration test):

```manuscript
interface Read:
    get value -> Int
type Counter:
    remaining: Int
impl Read for Counter:
    get value -> Int:
        if self.remaining <= 0:
            return 0
        self.remaining = self.remaining - 1
        return recurse(self)
fn recurse(counter: Counter, value: Int = counter.value) -> Int: value
```

Reviewer-owned native evidence:

- Merge: `Counter(210000)` completes successfully, `1 tests, 0 failed`, despite the runtime's `MaxCallDepth = 200000`. Emitted `call_symbol3` runs `method_32` from its default; `method_32` calls `call_symbol3`. Neither body contains `rt.Enter`.
- First parent: exactly the same accessor source faults with `call depth limit exceeded (200000 nested calls)`, alternating `Counter.value` and `recurse` source frames. The compiler was built with a Go overlay restoring every changed production Go file to first-parent content; the newly added closure file was replaced by an empty `package lower`. Generated source then compiled against the same current runtime (the runtime delta only adds `NamedFunc`). This isolates the lowering regression without editing either tree.
- Exact new main: exported `pkg/`, `internal/`, `go.mod`, and `go.sum` at `f253bf39`; used the unchanged shared vendor directory. An equivalent source with an ordinary `read(counter)` function instead of an accessor also completes 210000 iterations. The issue originates in #507 and is now exposed in accessor/default composition by the integration. It is not caused by retaining accessor flag counts in the merge conflict resolution.

Fix direction: retain each callable's parameters in SCC nodes and use the existing visitor's `Callable(params, body)` so expression-default edges join the graph. Preserve current sampled checks and defaults' callee scope/order. Add emitted-form and bounded native checks for default-only recursion and default/accessor cycles, including cancelled execution. No correction is considered reviewed by this report.

Evidence artifacts:

- `.artifacts/reviewer-e9849d26/default-cycle.ms`
- `.artifacts/reviewer-e9849d26/default-cycle.go` and native `default-cycle`
- `.artifacts/reviewer-e9849d26/default-cycle-first-parent.go` and native counterpart
- `.artifacts/reviewer-e9849d26/first-parent/overlay.json`
- `.artifacts/reviewer-e9849d26/default-cycle-no-accessor.ms`
- `.artifacts/reviewer-e9849d26/default-cycle-main-control.go` and native counterpart
- `.artifacts/reviewer-e9849d26/main/`: exported main compiler/runtime sources

The finding was sent promptly to the primary agent, which acknowledged it and is preparing a separate correction.

## Other inspected integration behavior

Consulted current AGENTS.md, architecture/development and vision guidance, manuscript-change, compiler, language-design, runtime and language-design-taste workflows, routed expert guidance for direct lowering, defaults, capture snapshots, checked identities, source frames and runtime boundaries. Read the approved accessor design and both saved prior independent review reports as historical evidence, without extending their approval to this merge.

Reviewed the complete first-parent production delta, the accessor/default and accessor/local-closure integration tests, the conflict resolution, local-closure eligibility/fallback, shared name/call/flag/scrutinee/capture classification, default initialization in direct bodies, direct callable selection, scalar and typed alternative result consumers, accessor reads as ordering barriers, SCC traversal and NamedFunc source registration.

No additional finding was established in the inspected paths. The conflict resolution preserves flags alongside calls/callSites, and the new tests cover the intended positive interaction. Reviewer probes expand that evidence:

- Captured scalar locals retain snapshot values while captured collection references observe later mutation.
- Direct local closures returning Optional/Result feed presence accessors and match consumers. Capturing an Optional local keeps the boxed fallback safe.
- A function-valued source accessor executes exactly once in an omitted default; supplying the parameter bypasses that default.
- An impure accessor executes before a failing compatible `try` inside a direct local closure.
- Error.message remains a method in concrete, interface-view and generic-bound local-closure paths.
- A deliberate fault inside a direct closure inside an accessor invoked from a default retains exact source lines and named `<anonymous>`, `State.value`, `defaulted`, and test frames.

These observations do not negate the recursion blocker above.

## Reviewer-executed checks

Pinned SDK: `/workspace/manuscript-accessor-design/toolchain/go/bin/go`; PATH begins with that bin directory. Environment: `GOCACHE=/tmp/manuscript-accessor-go-cache`, `GOPATH=/tmp/manuscript-accessor-go`, `GOFLAGS=-buildvcs=false`, `XDG_CACHE_HOME=/tmp/manuscript-accessor-cache`.

1. `git diff --check HEAD^1 HEAD`: PASS.
2. `go test ./pkg/lower -run 'PresenceAccessors|LocalClosures|Direct.*Default|Accessors' -count=1`: PASS.
3. `go test ./pkg/lower ./pkg/checker ./pkg/runtime -run 'Accessor|OmittedDefaults|DirectOnlyLambdas|ErrorMessage' -count=1`: PASS in all three packages (lower, checker, runtime).
4. Reviewer native `positive.ms`: PASS, `1 tests, 0 failed`.
5. Reviewer native `fault.ms`: deliberately exits 1 with `reviewer fault`; expected closure/accessor/default caller frame chain present.
6. Reviewer finite recursion probes: merge PASS versus first-parent expected depth fault; main ordinary-function control PASS, establishing the blocker.

Native probes use a small local Go driver importing this checkout's compiler, saving emitted source, and invoking pinned `go build` and the resulting executable. This checkout lacks `.build-payload.tar.gz`, so importing `pkg/build` directly failed at Go embed discovery. The probes therefore use normal Go builds of emitted programs against the exact runtime package, with no production workaround or source edit. They are not standalone/distribution or SDK-bundle checks.

## Limits and remaining work

Did not duplicate the primary agent's `make verify`, full e2e/build suites, fuzz diagnosis, release gates, race checks, documentation generation, extension/debugger suites or benchmarks. Linux/amd64 only. Positive probes and focused tests are not exhaustive proofs of generic combinations, cancellation/race behavior or every migration surface. Cancellation loss in the uncovered cycle follows from the emitted missing checks; this reviewer did not separately inject cancellation into that cycle. Native source frames were directly exercised.

The baseline-only CI CSV fuzz timeout is separate from accessors; no cause, flakiness claim, harness suppression or fix is established by this review. The primary agent owns its diagnosis.

Approval remains blocked on the recursion correction and exact correction re-review plus the primary agent's applicable fresh gates. Any later commit needs its own exact-diff judgment.
