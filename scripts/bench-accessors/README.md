# Accessor lowering measurements

Run the same harness against an unmodified method-era checkout and the accessor
checkout with the same pinned SDK. The source changes only at approved member
reads; `-legacy` spells those reads as calls. The harness resolves source symbols
through the selected compiler, then executes generated native loops. Compilation
and process startup are outside benchmark timing. Each reported operation runs
1024 reads; divide time by 1024 only when reporting per-read estimates, and retain
that denominator. The source wrapper and loop arithmetic remain in both results.

From the method-era checkout (replace `ACCESSOR_CHECKOUT` with an absolute path):

```sh
GOCACHE=/tmp/manuscript-accessor-bench-cache toolchain/go/bin/go run -mod=vendor ACCESSOR_CHECKOUT/scripts/bench-accessors/main.go -legacy -output .artifacts/accessor-bench-baseline -count 5 -benchtime 200ms
```

From the accessor checkout:

```sh
GOCACHE=/tmp/manuscript-accessor-bench-cache toolchain/go/bin/go run -mod=vendor ./scripts/bench-accessors -output .artifacts/accessor-bench -count 5 -benchtime 200ms
```

The harness retains `program.ms`, `program.go`, `program_test.go`, `accessors.test`,
`escape.txt`, `emission.json` and `samples.txt`. `-generate-only` stops before native compilation.
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
repeated-read cases retain the existing immutable-string shape cache.

Additional loops cover direct source accessors, explicit interface views, generic
bounds, uncontended guarded payload reads, live ClientResponse metadata, Duration
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
The baseline must emit the verified partition of 6 direct, 7 hoisted native-call,
and 7 full-binding paths; current core reads reject all callable dispatch forms.
Static reads should use typed
receiver-only helpers, with no bound Function, Invoke, Bind, CallNative,
BindNativeCall, or argument slice for the read. The handwritten/control cases
help distinguish dispatch changes from unrelated harness/compiler drift. Do not
claim that the already direct candidates must improve, or infer unmeasured
service/guard/dynamic-dispatch performance from these core loops.
