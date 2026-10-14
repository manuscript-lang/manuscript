# Accessor lowering measurements

Run the same harness against an unmodified method-era checkout and the accessor
checkout with the same pinned SDK. The source changes only at approved member
reads; `-legacy` spells those reads as calls. The harness resolves source symbols
through the selected compiler, then executes generated native loops. Compilation
and process startup are outside benchmark timing. Each reported operation runs
1024 reads; divide time by 1024 only when reporting per-read estimates, and retain
that denominator. The source wrapper and loop arithmetic remain in both results.

From the method-era checkout (replace `ACCESSOR_CHECKOUT` with an absolute path and commit placeholders with the measured revisions):

```sh
GOCACHE=/tmp/manuscript-accessor-bench-cache toolchain/go/bin/go run -mod=vendor ACCESSOR_CHECKOUT/scripts/bench-accessors/main.go -legacy -revision BASELINE_COMMIT -output .artifacts/accessor-bench-baseline -count 5 -benchtime 200ms
```

From the accessor checkout:

```sh
GOCACHE=/tmp/manuscript-accessor-bench-cache toolchain/go/bin/go run -mod=vendor ./scripts/bench-accessors -revision ACCESSOR_COMMIT -output .artifacts/accessor-bench -count 5 -benchtime 200ms
```

The harness retains `program.ms`, `program.go`, `program_test.go`, `accessors.test`,
`escape.txt`, `emission.json`, `metadata.json` and `samples.txt`. `-generate-only` stops before native compilation.
Select smaller groups with `-bench`, while retaining parity/cancellation tests.
Both runs use one CPU for native samples. Record compiler commits, SDK version,
CPU, environment (especially GOMAXPROCS/GOGC/GOMEMLIMIT), build flags, and the
commands alongside any statistical comparison of the sample files.

Twenty distinct candidate reads are measured individually: List/Map/Set length,
List is_empty, String byte_length/length, List first/last, Map/Set/Bytes/String
is_empty, String scalar_length, Bytes length, Optional is_some/is_none, Result
is_ok/is_error, and Float is_nan/is_finite. Data variants include empty/present
collections, ASCII/Unicode, both Optional/Result tags, NaN, infinities and signed
zero. The Optional/Result parameter cases intentionally measure boxed ABI values;
additional typed-local workloads construct some/ok before their read loops. String
repeated-read cases retain the existing immutable-string shape cache; an
alternating ASCII/Unicode workload exercises changes between texts, and boxed
List cases complement the primitive-backed List inputs.

Additional loops cover direct source accessors, explicit interface views, generic
bounds, uncontended guarded payload and logger threshold reads, live
ClientResponse metadata, Duration
seconds, and typed Optional/Result locals. Their setup runs once per 1024-read
operation and stays in both revisions. The guard loop includes lock acquisition
and scope cleanup. These isolate neither lock cost nor dispatch by themselves;
compare emitted code and runtime concurrency tests alongside them. The custom
source contract uses a method in legacy input and an accessor in current input.

`UnchangedMethodControl` uses List.at(...).unwrap() in both revisions. The
handwritten typed length control preserves checked arithmetic, loop polling,
native admission, source-function admission/delivery and the authoritative List.
It does not replace the receiver with a cached integer. Parity runs at 0, 1, 32
and 1024 iterations; cancellation tests verify the generated source wrapper's
admission. These do not replace runtime tests for cancellation during a contended
read, resource lifetime checks, or source fault line attribution.

Time check, emit and build separately with the retained N/2N/4N inputs:

```sh
python3 scripts/bench-accessors/scaling.py --baseline /absolute/path/to/baseline-ms --current ./ms --base-size 64 --count 3
```

This writes source, standalone emitted Go, native binaries and samples.json under
.artifacts/accessor-scaling. Each phase is warmed independently. Generated native
programs are executed to verify their checksums. Whole-phase timings include CLI
startup and should be assessed as scaling evidence, not accessor runtime speed.

Inspect generated Go in addition to timings. `emission.json` records runtime calls in each of the 20 core workload bodies.
The baseline partition is recorded from the compiler being measured; current
core reads reject all callable dispatch forms. Later main-branch optimizations
can change the historical audit partition, so never attribute those changes to
the accessor migration.
Static reads should use typed
receiver-only helpers, with no bound Function, Invoke, Bind, CallNative,
BindNativeCall, or argument slice for the read. The handwritten/control cases
help distinguish dispatch changes from unrelated harness/compiler drift. Do not
claim that the already direct candidates must improve, or infer unmeasured
service/guard/dynamic-dispatch performance from these core loops.

## Retained measurement, 2026-10-14

The [baseline metadata](results/baseline-metadata.json) identifies main at
measurement time, 1383851e; [accessor metadata](results/accessors-metadata.json) identifies
31d00fb7 plus the documented integration worktree. Both use the pinned Go 1.25.1
SDK on linux/amd64, one native benchmark CPU, five 200ms samples per workload,
and 1024 reads per operation. The native transcript records the Xeon 8573C host.
Generated Go, native binaries and escape reports remain in the ignored artifact
directories named above; their source hashes are retained in metadata.

- [All baseline samples](results/baseline-samples.txt), [all accessor samples](results/accessors-samples.txt), and [paired numeric samples](results/paired-samples.json).
- [Baseline emitted paths](results/baseline-emission.json) and [accessor emitted paths](results/accessors-emission.json).
- [Median/allocation comparison and exploratory exact permutation p-values](results/comparison.json).
- [Check/emit/build scaling samples](results/scaling.json), with three samples after warmup at each of 64, 128 and 256 reads.

The updated baseline has 8 direct, 7 hoisted and 5 bound paths: Optional flags
already use direct helpers, while Result flags, Float classifiers and Bytes
length still bind. The accessor versions of all 20 core reads use direct helpers.
The unchanged-method control's median increased by 0.94%; Unicode String.length
increased by 1.2% with no evidence of a timing shift in its five samples. Do not
claim that every getter improves or generalize these loops to application speed.
Later integration with #507/#508 has its own
[verification record](results/verification/main-integration-f253bf39.md); it does
not change this comparison baseline or its raw samples.
Permutation p-values are exploratory and have no multiple-comparison correction.

The handwritten control calls the existing generic CollectionLengthInt helper,
including its List/Map/Set receiver switch. It is a matching-semantics helper
control, not a claim about the fastest possible handwritten implementation.
Logger measurements include threshold equality, setup and cleanup; guard reads
are uncontended. These numbers do not isolate mutex cost or measure coordinated
contention. Local implementation evidence and contended cancellation remain
correctness tests rather than measured performance claims.
