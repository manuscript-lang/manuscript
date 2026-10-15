# Independent exact integration review

Request changes: one P1 correctness blocker established in immutable merge `8b4dd16f43b528ef8ad339460c6ceeb4ef5a4110` over first parent `fb66c3b4520bee9620962715e55a9298f09e05de`. The defect is inherited from newly integrated main `9dcc0bae` (#511), not introduced by the accessor conflict resolution. This is an independent review, not author self-approval or publication authorization.

## P1: key interface call-site cache by lexical implementation selection

Location: `pkg/runtime/methods.go:222-228`, called from `CallInterface` at lines 260-267 and populated at line 284.

`CallInterface` extracts each View's `Scope`, but `CallMethod` immediately calls `site.lookup(typ)`, whose entries contain only receiver concrete type and registration generation. Two views can have the same concrete type and contract but select different module-local implementations. Once the first view populates a site, calling that site with the second view executes the first implementation. This silently changes valid application results and ignores the language's lexical implementation evidence.

Concrete source reproduction is retained at `/workspace/manuscript-accessor-review-512/.artifacts/reviewer-8b4dd16f/scope/`. `domain.ms` declares nongeneric interface `Read`, source record `Reader(value: Int)`, and `invoke(view: Read) -> Int: view.read()`. `left.ms` and `right.ms` implement `Read` locally with `self.value + 10` and `self.value + 20`, then return interface views of `Reader(1)` and `Reader(2)` respectively. `main.ms` requires invoke(left()) == 11, invoke(right()) == 22, then invoke(left()) == 11. The emitted single call site in `invoke` uses `rt.CallInterface`. The second check fails, exiting 2.

Independent controls:

- Exact immutable merge compiler and runtime: reproduction exits 2 (FAIL).
- First-parent control: overlaid every changed production Go file back to exact fb66c3b4 bytes, leaving all other production inputs identical to that parent. Recompiled and executed the same source: exits 0 (PASS). Overlay and emitted output are retained in `parent-overlay/` and `scope_parent_generated.go`.
- Exact new-main `9dcc0bae` source snapshot from `git archive`, independently compiled and executed the same source: exits 2 (FAIL). Snapshot and output remain in `main-control/`.

The existing view-local implementation test uses separate concrete interface call sites and generic forwarding, so it does not reject this case. Add a regression that alternates two views with the same receiver type and different local implementations at the same nongeneric interface call site. The call-site identity must retain relevant lexical scope/module evidence, and must not permit a cached no-argument scope entry to bypass a later scope with type arguments. The global resolution cache already includes module and serialized scope arguments.

## Other reviewed integration behavior

Read current AGENTS.md, VISION, architecture/development guidance, manuscript-change/compiler/runtime/language-design/language-design-taste workflows, expert protocol/index and relevant compiler/runtime/language lessons; reviewed the approved accessor design and prior 789a4452 correction evidence. Inspected the complete 14-file merge diff, new integration test, inherited interface cache semantics, defaulted direct constructors and recursion accounting, native/String fast-path eligibility, and accessor helper reuse.

The conflict resolution continues to exclude Accessor from preparedMethodCall and scalar-native method selection. Source/interface accessors retain their separate executable member path. New direct default constructors are conservatively counted even though their field defaults are not direct-call graph Params; this retains a recursion checkpoint. The earlier 789a4452 default-expression visitor fix remains in place. String/Float accessor helpers call shared pure scalar algorithms while retaining their original path-specific cancellation checks, including StringLengthRead's admission-only path. No second concrete blocker was established in this review. Broad tests remain the primary agent's responsibility and are not represented here as independently run.

## Benchmark protocol review

Reviewed `/workspace/manuscript-accessor-design/.artifacts/verification/final512/contention-protocol.md` before samples and promptly communicated acceptance. The method is sound for its explicit scope: complete public method-era Bind/Invoke versus statically selected accessor, identical full-safety controls, construction/setup outside timing, Logger scalar/tag consumption without Equal/I/O, proven mutex-blocked reader before the timed release, and explicit release-to-result latency rather than throughput/getter-cost claims. It preserves live reads, validation and admission/delivery cancellation and calls for correctness/race probes before samples. Exact harness implementation and evidence still require subsequent review; protocol acceptance alone establishes no performance result.

## Evidence limits

All native probes used `/workspace/manuscript-accessor-design/toolchain/go/bin/go` with that bin first in PATH, GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS=-buildvcs=false, XDG_CACHE_HOME=/tmp/manuscript-accessor-cache. Native generated programs built directly against the corresponding exact runtime, without the unavailable build payload or production source changes. `git diff --check fb66c3b4 HEAD` passes. No tracked source edits, broad gate duplication, push, PR or merge actions performed. Linux/amd64 only.
