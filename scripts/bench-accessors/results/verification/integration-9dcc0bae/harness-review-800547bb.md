# Independent exact contention harness review

APPROVE the pre-sample harness at exact commit `800547bb60c0b7926f77572b1236a2c198043b12`, parent `1ff193c04a90965b969678f3a253c33220ca3edf`. No concrete blocker established. Measurement may proceed after the primary agent's broad verification is quiet. This approves the experimental implementation and its stated limits, not any performance conclusion, remaining release gates or publication.

Immutable review checkout: `/workspace/manuscript-accessor-review-contention`. Exact HEAD and clean tracked status verified. Full six-file diff read. `git diff 1ff193c0 HEAD -- pkg internal` is empty: production implementation remains the independently approved scope correction.

## Exact implementation versus approved protocol

The driver substitutes exactly two public adapters in one common runtime-package test template: historical guard.get / Logger.level use ordinary Bind plus Invoke; current reads call SynchronizedGuardValueRead / LoggerLevelRead. Independently generated baseline/current Go differs only at those two return statements. Receivers, Execution construction, synchronization, result shape, validation, safety controls, consuming operations and coordination remain common. No production overlay or optimized replacement runtime is introduced.

The identical guard control unwraps the receiver, checks cancellation, acquires the actual cell mutex, validates exact holder identity, reads live state, unlocks and checks delivery cancellation. The identical Logger control checks admission, unwraps its View, acquires the threshold mutex, captures live threshold, unlocks, produces the same LogLevel Alternative and checks delivery cancellation. The corresponding exact baseline method bodies and current helpers retain the same required safety semantics; historical wrappers add their existing dispatch and wrapper checks. Controls are measurement references rather than proposed replacement APIs.

The isolated Logger has no transport and performs no logging, formatting or I/O. Both results are consumed through an Int or Alternative.Tag sink; the benchmark does not call LogLevel Equal or a source function. Guard holder setup and cleanup occur outside timed reads and never bypass holder validation.

Uncontended timing resets after receiver/Execution construction and a validated setup read, includes each complete API/control call and sink write, then stops before cleanup. Blocked setup holds the actual receiver mutex, writes live state under it, starts exactly one named noinline reader, and scans its stack until it is demonstrably blocked in sync.Mutex Lock/lockSlow with a mutex-blocked/semacquire goroutine state. The reader routes contain no other contended application mutex. No sleep or scheduler-order assumption establishes blocking; setup is bounded by a five-second check and the test executable has an outer timeout. No other reader remains outstanding between iterations.

Only after that proof does the benchmark start its timer, unlock, await the reader outcome and stop timing. Result validation, sink consumption and the next setup remain outside timing. Therefore the result is release-to-result latency including unlock, scheduling and channel delivery. It excludes Bind/Invoke setup completed before the lock acquisition, and corresponding binding allocations, just as the README explicitly states. It cannot establish full-call throughput, pure getter cost, total allocations or an isolated dispatch speedup. The stack scan itself perturbs scheduling and forced blocking is synthetic; the documentation makes these limitations explicit.

Parity checks cover repeated live writes/reads, a mutex-blocked live read, cancellation triggered only after mutex-block proof and observed after release, and a stale closed guard checked with a fresh uncancelled Execution. Both public operations and controls use the same coordination. Channels join the read before Context mutation or cleanup, and normal/race runs pass.

The driver records exact tree commits, generated hashes, template hash, SDK/host/environment and commands, retains executables/overlays/logs, defaults to validation-only, and enables measurement only with --measure. Its measurement path alternates revision order, uses GOMAXPROCS=2 / test.cpu=2, retains five raw samples by default, checks the expected record count, and calculates medians per revision and benchmark case without significance/speedup thresholds. No benchmark results existed or were produced by this review.

## Independent validation and provenance

Ran exactly:

`GOCACHE=/tmp/manuscript-accessor-go-cache GOPATH=/tmp/manuscript-accessor-go XDG_CACHE_HOME=/tmp/manuscript-accessor-cache python3 scripts/bench-accessors/contention.py --baseline /workspace/manuscript-accessor-baseline --current /workspace/manuscript-accessor-review-contention --go /workspace/manuscript-accessor-design/toolchain/go/bin/go --output .artifacts/reviewer-800547bb/validation`

PASS: baseline/current normal and race parity probes, measurements=False. The exact driver metadata, commands, build logs, parity logs, overlays, generated Go and binaries are retained under `/workspace/manuscript-accessor-review-contention/.artifacts/reviewer-800547bb/validation`. Baseline commit is `1383851ebb24d2dc8a0a13d8cec0021bf32e833d`; current commit is the exact reviewed 800547bb. SDK is Go 1.25.1 linux/amd64. No benchmark flag or measurement was used.

Template SHA256 at this commit is `95f53ebd231c8f947be8f447437c237d6f92b77a0db67d459d36af9cd97e3ea3`. Its generated, gofmt-normalized output is byte-for-byte identical to the primary agent's earlier validated artifacts, despite the earlier metadata's pre-formatting template hash:

- Baseline generated SHA256: `a4b022de2eb4f0fa3b80535ea45ca76dd28c8cd42d27decc7c46ffa0eae2c119`.
- Current generated SHA256: `90ca6eb3a5e43dab282f30e5864e8ec4b90918ee534ac63710671a24d30ef6fd`.

`git diff --check 1ff193c0 HEAD`: PASS. No untracked pkg/internal sources in the review tree. The baseline has an untracked toolchain entry; the recorded command explicitly selects the same pinned SDK for both revisions, and no production source change is involved.

## Fixture formatting

The three source fixture changes preserve semantics: first/second import the same names from the same path in the same order, with line breaks and a blank line between operations; main wraps the unchanged ordered `or` expression in parentheses and line breaks. The existing expression was already one condition, so grouping changes neither evaluation order nor short circuiting. Source line positions naturally change with formatting. No declarations, operands, calls, accessors, assertions or imports were added or removed relative to the approved correction.

## Limits

This is a focused pre-sample review, not independent execution of broad build/e2e/format/documentation/distribution gates. Linux/amd64 only. The experiment intentionally uses a forced single blocked reader and does not model real workload contention or prove a statistically significant improvement. Review the actual raw samples/control behavior before making any performance claim. The primary agent remains responsible for the final exact-code verification matrix and user publication authorization. No source edits, push, PR, publication or merge performed.
