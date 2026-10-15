# Accessor integration with merged #507 and #508

Publication remains held: no push or PR. The seven original verification/review
chunks were returned verbatim as separate numbered messages; their saved files
and manifest remain unchanged at `chunks/` beside this record.

## Exact revisions and integration

- Previous feature/evidence: `f508ab6ea2f9adb2eb26895643429e5d39a3a935`.
- Fetched main: `f253bf399d0b60d27e2b5fe8af4ae085e56c6a98`, containing #507
  (`1b16883d`, direct omitted defaults) and #508 (direct local closures).
- Local merge: `e9849d26218ce0361df86349956b1c11ad502d07`.
- Reviewed correction: `789a4452816128fae9de7d1b515543897279abe7`.

One conflict in `lower_alt_lets.go` was resolved by retaining accessor flag counts
and the incoming closure call counts/sites on the same use inventory. Two new
#508 fixture calls changed from `length()` to `length`. Added regressions execute
live reads in direct closures, typed Optional/Result flags, default getters after
supplied arguments, and explicit arguments bypassing default evaluation.

## Independent review and correction

The immutable merge review requested changes for one P2 blocker. #507 admits
default-bearing functions to direct lowering, but `markCounted` visited only their
bodies. A cycle through a default expression and source accessor omitted sampled
depth/cancellation accounting. A bounded 210,000-step probe incorrectly completed;
the first-parent accessor implementation correctly faulted at MaxCallDepth.
The reviewer reproduced the same defect on exact main using ordinary functions,
establishing an inherited #507 defect rather than a conflict-resolution error.

Correction `789a4452` retains each declaration in the recursion node and visits
its parameters/defaults and body through the existing Callable visitor. It adds
emitted-form and bounded native depth/cancellation regressions and records the
lesson. Restoring the old traversal with a Go overlay makes the new lowering test
fail for both members of the cycle. Corrected focused suites pass (lower 1.461 s,
build 7.706 s).

The independent exact-diff re-review **APPROVED** the correction with no new
findings. Its original accessor probe and exact-main ordinary-function control
now fault at the depth limit; its positive integration probe still passes.
Reports remain unchanged under `integration-f253bf39/`.

## Verification on the integrated source

Both initial merge and corrected commit pass `make -o payload verify`. The final
full lower/compiler suites pass at `789a4452` (0.215 s / 0.762 s).
The initial full build/e2e suites passed but missed the review blocker.
Corrected full build/e2e pass (189.895 s / 190.179 s), with 596/366 passing test
events, zero failures and zero skips. Book/publication checks also pass.

Commands use pinned Go 1.25.1, writable caches, `GOFLAGS=-buildvcs=false -p=2`,
fresh `-count=1`, a 30-minute timeout and corrected native `-parallel 2`, without
test filters. The test-exec shim retains the helper-build VCS workaround. Logs:
`.artifacts/verification/integration-<revision>-*.log` or `*.jsonl`.
No surviving suite was duplicated.

## Baseline CSV fuzz failure: evidence and limits

Main [run 38648209971](https://github.com/manuscript-lang/manuscript/actions/runs/38648209971)
ran exact `f253bf39`, without this unpublished branch. All three Go shards and
macOS/Windows host checks passed; static/fuzz failed in `FuzzCSVRoundTrip` after
102,384 executions in 11 s with `context deadline exceeded`. No crashing input,
stack, or minimization was reported; later editor/DAP steps were skipped.
This is a baseline failure, not evidence of an accessor regression or a fixed CI.

The CSV target uses RootExecution and has no operation deadline. The pinned Go
coordinator creates a timeout parent and a cancellable worker child. Its stop
function suppresses the error only when it equals the child's current Err.
Context cancellation closes the parent's Done before propagating to children.
Thus a scheduling gap can retain DeadlineExceeded as an error during normal
timeout shutdown. A standalone public-context model widened with sibling contexts
demonstrates that gap and suppression result in 6/10 runs. The sibling count
amplifies the window; it is not the coordinator topology or a failure-rate
estimate. No SDK or repository runtime code was changed by the probe.

All bounded follow-ups pass: six timed CSV runs on exact main (three with Go
debug logging), three on the integrated runtime, one 100,000-execution-budget run
per revision, and 80 short no-op fuzz controls without Manuscript. The corrected
commit changes no runtime/fuzz-target dependency source. These runs share warmed
corpora and do not recreate the unknown CI inputs or execution schedule.

The coordinator race is a concrete mechanism capable of this error, **not proof
of the exact failed CI cause**. The failure is not dismissed as flaky or declared
fixed. Exact attribution remains open without a reproducer or shutdown trace.
No fuzz failure was suppressed, target weakened, or CI workflow changed. Sources,
run records and context observations are saved under `integration-f253bf39/`;
complete raw logs remain in `.artifacts/verification/fuzz-csv-integration/`.

## Benchmark and platform boundaries

All nine original benchmark result files remain byte-identical to `f508ab6e`;
their comparison baseline remains `1383851e`, separate from this newer main.
Generation-only checks at the merge and corrected commit retain all 20 direct
core helpers and reproduce the archived source/emitted-Go hashes. No new timing
samples or performance conclusions are asserted.

Prior combined coverage (78.0%) belongs to reviewed `12a26d19`, not this integration.
Corrected runtime/checker/lower source builds pass for Linux ARM64, both Darwin
targets and both Windows targets. Native execution/distribution gates still need
their CI runners; cross-builds do not establish native behavior.
