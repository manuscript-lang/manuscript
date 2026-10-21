# Manuscript vs handwritten Go

## Latest: Rust `ms` (2026-10-20)

Median of 5 alternating runs at 100M iterations for the loop rows; linux/amd64, four cores, Go 1.25. Checksums and operation counts verified. Ratios are Manuscript time over Go time, so below 1.00x is faster than Go.

| operation | Manuscript ns/op | Go ns/op | ratio |
|---|---:|---:|---:|
| string_append_50k | 9.75 | 4.62 | 2.11x |
| read_line | 118.88 | 116.27 | 1.02x |
| map_put_get_8k | 37.17 | 41.52 | 0.90x |
| int_eq | 2.29 | 1.38 | 1.65x |
| generic_call | 1.36 | 0.69 | 1.98x |
| method_call | 1.35 | 2.31 | 0.59x |
| try | 1.93 | 0.62 | 3.10x |
| match | 3.11 | 2.16 | 1.44x |
| builtin_length | 2.16 | 0.64 | 3.35x |
| for_list | 2.24 | 0.57 | 3.93x |

Single-operation loops range from faster than Go to about 4x slower. Go inlines or vectorizes several of these loops, so those ratios are real code-generation gaps and the current optimization target. Whole-program kernels, which are closer to real code, are on par with Go: see [`../kernels/README.md`](../kernels/README.md).

Everything below this line was measured on the earlier Go backend and is kept as history.

All 10 complete workloads measure within about 9% of raw handwritten Go or faster
in the final 30-trial run. Matching improves 3.41 to 1.76 ns/op versus Go's 1.65;
try measures 0.60 versus 0.60. These are measured workload results, not a promise
of exact equality on every input, host or run. The separate manual-index control
measured matching at 1.16x Go; retain it alongside the final 1.07x result.

2026-10-18 UTC; Go 1.25.1, linux/amd64, AMD EPYC 9V74, four-vCPU quota.
Baseline **02be6a39** (merged PR697). Thirty balanced trials share original raw-Go
samples, fixed sources, input, operation counts and verified checksums. All binaries
use CGO_ENABLED=0, -buildvcs=false, -trimpath, -ldflags='-s -w -buildid=' and ordinary
inlining. No builds or tests overlap sampling.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 2.29 | 2.28 | 3.23 | 0.71x |
| read_line | 62.57 | 60.40 | 65.12 | 0.93x |
| map_put_get_8k | 34.11 | 34.59 | 31.68 | 1.09x |
| int_eq | 1.00 | 1.00 | 1.00 | 1.00x |
| generic_call | 0.05 | 0.05 | 0.28 | 0.18x |
| method_call | 0.04 | 0.04 | 0.30 | 0.14x |
| try | 0.62 | 0.60 | 0.60 | 0.99x |
| match | 3.41 | 1.76 | 1.65 | 1.07x |
| builtin_length | 0.05 | 0.05 | 0.29 | 0.16x |
| for_list | 0.38 | 0.37 | 0.36 | 1.02x |

A bounded private clone removes redundant Int overflow checks for one fixed,
exhaustive pure alternative match over a closed literal list. Its caller inherits
only the proved call's result interval. The original general function and source
registration remain. Only approved gets whose index is proved nonnegative and
in range use ordinary Go Items[index], retaining Go's bounds check and exact index
evaluation. Unknown, negative, defaulted, aliased, captured, mutated, generic,
local-evidence and Debug paths retain the checked behavior. No representation or
public ABI changes. Remainder adds a value fact only, not unchecked arithmetic.

The caller-proof-only alternative removes about 3.5% of matching time; the actual
clone-only compiler still measures 1.39x Go. Their complete raw controls and the
direct-index control justify the final combination. No padding or placement tuning
is retained. Earlier loop batching preserves logical operation counts while doing
less unobserved work between the original cancellation queries.

All 66 library rows and 30 trials are retained. The generated library source and
normalized executable are byte-identical before/after this increment, so their
timing variation does not establish an algorithm regression. Compiler selection,
concurrent determinism, exact native effects/cleanup/fault frames, Release/Debug,
separate/standalone, signed and endpoint proofs, race checks, make verify and book
checks pass. Accepted 128/256/512-site scaling checks validate actual selected gets;
512-site emission is about 0.21–0.24 s and 91 MB with approximately linear allocations.

[Raw trials, hashes, intervals, all library rows, generated Go and controls](../results/2026-10-18-linux-amd64/bounded-match-index/).
[Canonical proof boundaries](../../../documentation/contributing/compiler/lowering/_index.md).

## Earlier closed-builder and traversal batch


Nine of ten complete workloads are within about15% of raw Go or faster after
closed-builder batching and ordered traversal unrolling. Builder is2.13ns/op
versusGo3.53; traversal0.38versus0.34. Matching remains2.19x the raw unchecked Go
baseline. A separate arithmetic/cancellation-equivalent handwritten-Go control
measures3.18ns versusManuscript3.44 (1.08x). That control diagnoses the cost; it
does not replace the raw baseline or establish that the residual is unavoidable.

2026-10-18 UTC; Go1.25.1, linux/amd64, AMD EPYC9V74, four-vCPU quota.
Baseline **f58ad141** (merged PR696). Thirty balanced trials, identical sources,
counts and checksums; matching CGO_ENABLED=0, -buildvcs=false, -trimpath,
-ldflags='-s -w -buildid=' and ordinary inlining. No builds/tests overlap sampling.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 3.66 | 2.13 | 3.53 | 0.60x |
| read_line | 60.83 | 58.75 | 63.73 | 0.92x |
| map_put_get_8k | 33.07 | 34.58 | 30.95 | 1.12x |
| int_eq | 1.05 | 1.03 | 0.99 | 1.05x |
| generic_call | 0.05 | 0.05 | 0.27 | 0.19x |
| method_call | 0.04 | 0.04 | 0.28 | 0.16x |
| try | 0.59 | 0.65 | 0.56 | 1.15x |
| match | 3.53 | 3.46 | 1.58 | 2.19x |
| builtin_length | 0.05 | 0.05 | 0.28 | 0.17x |
| for_list | 0.44 | 0.38 | 0.34 | 1.11x |

Builder batching requires a fresh private canonical builder, exhaustive direct
uses and every freeze after every append-containing top-level statement. Only
literal fragments up to128 decoded bytes qualify. The native append still checks
sealing. Traversal retains every original addition/subtraction in order, snapshots
Items, and binds the next element before its original query. A fixed three-update
unroll amortizes control. Both preserve exact source-visible query state, partial
tails, cancellation, cleanup and fault lines; aliases, captures, unknown bounds,
effectful fragments, other bodies and Debug fall back. Logical source operation
counts stay unchanged while selected loops perform less invisible work.

The library's generated Go and normalized executable are byte-identical before
and after this increment. All66 rows and30 trials are retained as a diagnostic
control; their timing variation is not attributed to an algorithm change. The
initial1024-byte literal cap produced34MB Go/~496MB allocation for512 sites;
reduce to128 (8064 repeated bytes/site). Both cap variants emit byte-identical
benchmark programs and executables; final scaling controls are retained.

[Raw trials, hashes, intervals, all66 library rows, scaling and rejected controls](../results/2026-10-18-linux-amd64/closed-builder-range/).
[Canonical proof boundaries](../../../documentation/contributing/compiler/lowering/_index.md).

## Earlier counter-aggregation batch


Safe aggregation closes the generic, method, and length loop gaps. Their times
are per logical source iteration: the compiler combines unobserved updates
between identical cancellation queries, reducing work. It does not execute each
original assignment faster. Try is at Go parity in this run. Matching and the
builder remain the current gaps under investigation.

2026-10-18 UTC; Go1.25.1, linux/amd64, AMD EPYC9V74, four-vCPU quota.
Baseline: **ec818c1f** (merged PR #695). Thirty balanced trials, identical sources,
counts and checksums; matching CGO_ENABLED=0, -buildvcs=false, -trimpath,
-ldflags='-s -w -buildid=' and ordinary inlining. Sampling overlaps no builds/tests.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 3.81 | 3.65 | 2.85 | 1.28x |
| read_line | 59.41 | 61.08 | 63.66 | 0.96x |
| map_put_get_8k | 34.94 | 35.14 | 32.08 | 1.10x |
| int_eq | 1.02 | 1.03 | 1.03 | 1.00x |
| generic_call | 0.32 | 0.05 | 0.27 | 0.19x |
| method_call | 0.64 | 0.04 | 0.28 | 0.15x |
| try | 0.62 | 0.58 | 0.56 | 1.03x |
| match | 3.47 | 3.62 | 1.57 | 2.31x |
| builtin_length | 0.33 | 0.05 | 0.27 | 0.17x |
| for_list | 0.45 | 0.43 | 0.38 | 1.13x |

Aggregation admits only the existing finite two-update loop grammar with safe
original prefixes and separately proved generated temporaries. It combines at
most63 bodies, preserves exact counter/carry state at every original query, then
executes the original queried body. Captures, aliases, defaults, effectful strides,
unknown arithmetic and Debug retain the ordinary path. Native observers cover
signed updates, extreme counter starts, partial tails, nil/background/shield,
cancellation, cleanup, query faults/source frames and standalone linkage.

[All program trials, 66 library rows, intervals, hashes and controls](../results/2026-10-18-linux-amd64/counter-aggregation/).
[Canonical proof boundaries](../../../documentation/contributing/compiler/lowering/_index.md).

## Earlier Result-bound batch


Eight of ten workloads are within roughly 20% of Go after the successful Result
payload proof. Try is 0.63 ns/op versus Go's 0.56, down from 1.16 ns/op in the
merged baseline. Method loops and matching remain the largest gaps. These are
complete workloads with identical counts and checksums, not isolated instructions.

2026-10-18 UTC; Go 1.25.1, linux/amd64, AMD EPYC 9V74, four-vCPU quota.
Baseline: **0bac0cbd** (merged PR #694). Both revisions compile the same benchmark
sources. Thirty trials cycle all six Go/before/after orders with shared Go samples.
Builds and correctness tests finish before sampling; TMPDIR/GOTMPDIR are unset.
All three executables use CGO_ENABLED=0, -buildvcs=false, -trimpath and
-ldflags='-s -w -buildid=' with ordinary inlining.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 3.22 | 3.36 | 2.81 | 1.20x |
| read_line | 56.16 | 57.97 | 63.12 | 0.92x |
| map_put_get_8k | 32.53 | 32.99 | 31.64 | 1.04x |
| int_eq | 1.01 | 1.02 | 0.97 | 1.05x |
| generic_call | 0.31 | 0.32 | 0.27 | 1.17x |
| method_call | 0.61 | 0.65 | 0.28 | 2.37x |
| try | 1.16 | 0.63 | 0.56 | 1.11x |
| match | 3.61 | 3.41 | 1.51 | 2.26x |
| builtin_length | 0.62 | 0.32 | 0.28 | 1.16x |
| for_list | 0.62 | 0.45 | 0.39 | 1.16x |

The new proof summarizes only normal successful values of a fixed checked helper:
one immutable Int parameter, one pure comparison with a literal-only early error,
then ok(parameter plus/minus an Int literal). At most one exact Result identity
wrapper hop is admitted. All original calls, allocations, errors and general
arithmetic checks remain. Success facts are scoped to their if-let arm. Finite-loop
delta collection invalidates every modified peer, retains both branches' separate
positive/negative budgets, and never transfers evolving accumulator values.
Unknown helpers, defaults, hidden successful returns, aliases, generics and Debug
fall back. No error impossibility or call totality is inferred.

The library's generated Go and normalized executable are byte-identical before
and after this increment. Thirty diagnostic CLI-built library runs preserve all
66 counts/checksums; their code/data sections match and only build-id notes differ.
The complete diagnostic timing variation is retained rather than attributed to an
algorithm change. Summary allocations scale 1421/2831/5649 at 128/256/512 helpers;
proof allocations scale 2903/5742/11416. Timing profiles accompany the raw scaling.

[Raw trials, hashes, intervals, controls and reproduction](../results/2026-10-18-linux-amd64/result-payload-bounds/).
[Canonical proof boundaries](../../../documentation/contributing/compiler/lowering/_index.md).

## Earlier merged batch

The following results and retained changes describe PR #694 before main advanced.
They remain historical evidence; the latest table above is the current candidate.


Seven of ten complete workloads are within roughly20% of handwritten Go in this
run. Method calls improve about8x, try about3.4x, and map put/get about1.9x over
the previous merged compiler. Parity remains incomplete: generic accumulation,
try and checked matching still cost more than the Go control.

2026-10-18 UTC; Go1.25.1, linux/amd64, AMD EPYC9V74, four-vCPU quota.
Baseline: **d710e9bf68845ce8a23e2de3f91836459396dafe** (PR#688).
Both revisions compile identical current benchmark sources. Thirty trials cycle
all six Go/before/after orders and share the same Go samples. All counts and
checksums match. Builds and correctness checks finish before sampling, with no
simultaneous compiler/test work.

All final executables use CGO_ENABLED=0, -buildvcs=false, -trimpath, and
-ldflags='-s -w -buildid=' with ordinary Go inlining. The inherited Go control
used by earlier experimental tables had default CGO/trim/link settings; those
controls are historical. The benchmark script now uses the matching flags.

| operation | before ns/op | after ns/op | Go ns/op | after / Go |
|---|---:|---:|---:|---:|
| string_append_50k | 3.94 | 3.52 | 2.93 | 1.20x |
| read_line | 87.39 | 66.13 | 67.24 | 0.98x |
| map_put_get_8k | 67.01 | 36.00 | 34.01 | 1.06x |
| int_eq | 1.11 | 1.08 | 1.01 | 1.07x |
| generic_call | 0.89 | 0.64 | 0.27 | 2.36x |
| method_call | 2.71 | 0.33 | 0.29 | 1.14x |
| try | 2.75 | 0.80 | 0.56 | 1.43x |
| match | 4.33 | 3.52 | 1.59 | 2.21x |
| builtin_length | 0.87 | 0.33 | 0.28 | 1.18x |
| for_list | 0.94 | 0.46 | 0.40 | 1.16x |

## Retained changes

- Exact adjacent Result unwrap/rewrap tails return the original Result once.
  Other try expressions still test failure and return the error directly.
  Mutable bindings, type/error conversions, function payload ABI and Debug keep
  their existing paths.
- Function-local exact intervals remove only proved-safe Int +, - and * checks.
  Finite loops budget every prefix, invalidate all modified peers before deriving
  deltas, and isolate callable/branch facts. Unknown arithmetic remains checked.
- A complete use inventory permits private Int-list length/element bounds and
  exact one-field record updates. Aliases, captures, unsupported mutations,
  defaults and unknown arguments retain ordinary semantics and calls.
- Closed Map[Int,Int] uses exclusive helpers inside the same Go type/layout.
  Its index maps keys to values, so every consumer must select together. Ordered
  iteration, formatting, aliases, custom evidence and Debug retain ordinary maps.
- Only the reviewed two-scalar constant-stride loop shape groups polling control.
  Each original assignment executes individually. Queries occur at the identical
  64th/128th/... body states, including partial chunks and signed endpoints.
- A canonical Bool read_line presence tail omits its unobserved final String.
  UTF-8, limits, consumption, locking, errors, custom reads and cancellation query
  counts stay intact. An8192-line runtime batch drops8192 allocations to zero;
  ordinary text-returning reads remain steady in seven alternating controls.
- Checked add/multiply share their original predicates through fixed cold fault
  callbacks. Fault messages, eager source stacks, cleanup and the32-bit multiply
  fallback remain intact. Subtraction and negation retain their implementations.
- File metadata construction removes temporary maps and discarded BigInt objects.
  Its fourteen exact values/order and unsigned widths remain intact. The isolated
  control drops66→52 allocations for metadata,70→56 for stat, with about21% lower
  stat time. Final full-library stat improves about24%.

The [canonical lowering rules](../../../documentation/contributing/compiler/lowering/_index.md)
and [storage contract](../../../documentation/contributing/go-lowering-representation.md)
state the proof boundaries.

## Remaining gaps and measured alternatives

The labels time complete loops. Generic identity already disappears into native
addition; its remaining loop has cooperative polling, spills and code-alignment
sensitivity. Identical hot instructions relocated by32bytes varied around0.34–0.64ns
in controlled builds. Canonical Go post clauses, outlining existing polling and
broader chunks moved which tiny kernels won but regressed other kernels. No
padding, special Go optimization flags, or lucky-placement tuning ships.

Try still performs required checked arithmetic in its general source helper and
caller. Matching still checks multiplication for arbitrary case payloads. The Go
control uses unchecked machine arithmetic and has no cooperative polling. These
identify current costs; they do not prove that further safe optimization is
impossible. No claim of complete parity or a performance ceiling is made.

A map key-presence proof saved only about6% in a manual control and was deferred:
line payload elision already removed most of the complete map row's remaining
allocation/collection pressure. Global fault/cancellation changes and all-four
arithmetic outlining were rejected for wider regressions. The
[proposal/review record](parity-plan.md) labels every retained and rejected scope.

## Library precision and regression controls

The library harness now prints consumed checksums and raw elapsed nanoseconds
outside the timed region. The validator checks every one of66 names, counts,
checksums and elapsed/rounded-row consistency on every execution. Ratios use raw
elapsed/ops, fixing the previous integer rounding of small rows.

The [complete library table](../stdlib/results.md) retains nominal slowdowns as
well as gains. Earlier allocation changes move later collection pauses. Focused
runs repeat an unchanged body20times in each of15 balanced processes; the large
full-run string/map/encoding/fold/archive slowdowns do not reproduce there.
Those controls and paired intervals accompany the full data, rather than replacing
it. Collection-phase observations are not a claim that all differences are noise.

Compiler proof-only allocation counts scale3683/7196/14210 at128/256/512 mixed
loops. Median times are1.66/3.48/7.57ms. Profiling excess timing growth shows
collector scanning at about28% cumulative; visited-node maps and undo journals
avoid repeated subtree scans or whole-fact-map copies. Scalar-only proof medians
are0.43/0.90/1.72ms; end-to-end compile medians5.12/11.86/22.17ms include checking,
printing and GC. These are compiler costs, separate from native execution gains.

## Evidence and reproduction

[Raw trials, controls, flags, source/binary hashes and intervals](../results/2026-10-18-linux-amd64/complete-parity/).
Older result directories remain historical. The final primary comparison uses
matching flags; intermediate experimental Go ratios are not the final parity result.

```sh
make build
BENCH_OUTPUT=.artifacts/perf-programs sh bench/perf/programs/run.sh 30
python3 bench/perf/programs/compare.py --before /path/to/before-program --after /path/to/after-program --go /path/to/go-control --input .artifacts/perf-programs/lines.txt --output .artifacts/program-comparison --repeats 30
python3 bench/perf/compare_stdlib.py --before /path/to/before-library --after /path/to/after-library --output .artifacts/library-comparison --repeats 30
```

Build both library revisions with the current harness so checksums and raw elapsed
comments exist on each side. Obtain the baseline compiler from a separate d710e9bf
worktree; invoke it on the same current benchmark projects and pinned SDK.

Validation: make verify; go test ./...; make conformance (223files,0failed);
make race; make book-check using CI's Hugo0.146.7; host make dist-check (packaged
compilation, source tooling, LSP, terminal/DAP debugging and profiles without host
Go/dlv/downloads); Python evidence tests. Source frames, cancellation state,
cleanup, payload identity, defaults/aliases, Debug and standalone paths are called
natively. Other platform execution remains CI coverage.
