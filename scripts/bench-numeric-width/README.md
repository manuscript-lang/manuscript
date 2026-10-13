# Default numeric-width migration controls

This directory records Go storage controls and runtime measurements for [#271](https://github.com/manuscript-lang/manuscript/issues/271). Initial controls compare explicit Go layouts on the signed64/binary64 baseline. The runtime samples compare default scalar results before and after the coordinated signed32/binary32 switch; the migration remains a draft requiring parent review and exact-head gates.

Use only the repository's pinned SDK:

```sh
GOCACHE=/tmp/ms-width-cache GOPATH=/tmp/ms-width-path \
    toolchain/go/bin/go build -o /tmp/ms-width ./scripts/bench-numeric-width
/tmp/ms-width -case layout
/tmp/ms-width -case boxed-int32 -n 1000000
/tmp/ms-width -case boxed-int64 -n 1000000
/tmp/ms-width -case typed-int32 -n 1000000
/tmp/ms-width -case typed-int64 -n 1000000
/tmp/ms-width -case boxed-record32 -n 100000
/tmp/ms-width -case boxed-record64 -n 100000
```

Other cases replace `int` with `float` or use `typed-record32/64`. Run each case in a fresh process for RSS, alternate widths, retain all samples, and use an idle/pinned host for timing conclusions. There is no external Go toolchain, profiler, benchmark dependency, or downloaded module. `reflect.Type.Size/Align` measures layout; `runtime.MemStats` measures allocation and heap retained after GC; Linux `/proc/self/status` reports current and high-water resident memory in KiB. RSS is process-wide and includes the runtime, code, stacks, allocator reserves and GC headroom. Other OSes omit that field.

Values avoid Go's small integer box cache. Generation stays within signed32, and traversal checksums deliberately accumulate into a wide host float64. Each scalar traversal reads equivalent values. Both record controls read the integer field; the boxed control uses the current `rt.Record`/field-map ABI. These controls do not include Manuscript invocation, cancellation, append growth, Optional wrapping or comparator callbacks, so they cannot replace generated-native benchmarks from the scalar/List owners.

## Measured layout and storage

Linux/amd64, pinned Go 1.25.1, three fresh processes per case. Raw samples are in `samples-linux-amd64.json`; there were no isolated CPU/timing conditions.

| Layout | 32-bit | 64-bit |
| --- | ---: | ---: |
| Scalar size / alignment | 4 / 4 | 8 / 8 |
| Boxed interface slot | 16 / 8 | 16 / 8 |
| Slice header | 24 / 8 | 24 / 8 |
| Typed `{integer, float, bool}` record | 12 / 4 | 24 / 8 |
| Typed `{String, integer, float}` record | 24 / 8 | 32 / 8 |

The runtime List header is 48 bytes/alignment8, Record 24/8, and Alternative 56/8. Their map/interface/payload headers do not shrink when a numeric payload changes width.

| Control | Elements | Retained heap32 | Retained heap64 | Approximate reduction |
| --- | ---: | ---: | ---: | ---: |
| Boxed Int/Float slice | 1,000,000 | 20.007 MB | 24.007 MB | 17% |
| Typed Int/Float slice | 1,000,000 | 4.006 MB | 8.004 MB | 50% |
| Current map-backed records | 100,000 | 38.406 MB | 39.206 MB | 2% |
| Typed numeric records | 100,000 | 1.204 MB | 2.400 MB | 50% |

MB here is 1,000,000 bytes. Small runtime/GC allocation differences appear in the raw samples. Boxed scalar controls perform about 1M allocations, versus 2-4 for typed controls. Both boxed record controls perform about 500K allocations; typed record controls perform 2. Narrower payloads reduce bytes, not box count. The typed record layout is a control, not a proposed replacement for mutable/recursive record identity or a completed #252 design.

Scalar RSS samples range roughly 29,800-34,100 KiB boxed and 14,200-18,300 KiB typed, with the 32-bit cases at the lower end. Corrected boxed-record samples are about 49,400 versus50,400 KiB. Fixed process overhead prevents interpreting any of these as a 50% RSS reduction.

Timing is inconclusive under shared load: boxed scalar construction varies from roughly 49ms to 1.20s and traversal from 29ms to 2.26s. The raw construction/traversal durations establish that timing was measured; they do not support a speedup claim. Retained heap and allocation counts are much more stable. Re-run paired/pinned generated workloads after the actual ABI migration, including identity/forwarding, at/unwrap, callbacks, sorting and mutation snapshots.

## Migration stages and compatibility

1. Explicit Int64/Float64 scalar identities, conversions, exact-width parsing and contextual literals. Parent's design revision avoids new literal suffix syntax: an explicit annotation/parameter or known matching-width operand selects the literal before parsing and rounding. Unconstrained literals will default 32. Typed variables never auto-promote. Cover default arguments, record/collection fields, generic result evidence, Optional adaptation, callbacks and matches.
2. Retain wide time, offsets/sizes, cumulative counters, OS metadata and TOML/binary64 codec contracts in `.ms` source and native registrations. Preserve JSON/YAML number text rather than inventing Float64 payloads. Convert small native results only after representability checks; preserve absence/errors/zero/negative unlimited sentinels and actual host errors.
3. Switch default checker ranges, min-literal handling, generated scalar types, runtime boxes/checked arithmetic, binary32 per-operation rounding/conversion/formatting/parsing together. Do not narrow only Go storage, promote arithmetic implicitly, or round an explicitly 64-bit literal through32 bits first.
4. Migrate source/native/ABI tests and docs; preserve the historical pre-AST golden and 64-bit benchmark evidence. Coordinate #259/#255 scalar maps, #142/#253 collections, #168/#265 faults, #173 defaults, #166 APIs and #172/#174 host work. No competing representation implementation is merged.
5. Parent reviews the complete transition before merge. Exact-head full CI, all six distributions and copied bundled-only standalone validation are required. Local controls or an additive wide stage do not approve the default switch.

Expected breaks include formerly accepted unconstrained integers outside signed32, Float precision beyond 2^24, overflow/fault boundaries, round-trip text, numeric generic evidence, host signatures and debugger concrete types. A default 32 scalar saved into a wide context after it was already bound requires explicit conversion; that conversion cannot recover discarded Float32 precision. Public 32-bit literal context and wider arithmetic do not authorize mixed-width variable arithmetic. Decimal stays 34-digit base 10 with its existing independent rounding/range rules. Default Int has no source shift/bitwise operators; the existing BigInt bit operations remain arbitrary precision.


The wide-host stage preserves Duration/Instant signed64 arithmetic independently of default Int helpers. Duration unit outputs/factors/divisors, Timestamp Unix seconds/construction, file offsets/lengths/metadata, memory/CPU/resource counters and byte budgets are explicit Int64; host load averages and TOML float payloads are Float64. Binary integer wire values remain Int64, and explicit read_float64/write_float64 preserve binary64 encodings. JSON/YAML numbers retain exact text. Source stream fakes and byte-budget checks convert explicitly while preserving omission, none, zero, negative bounds and payload identity. The switch uses public int32 hashes with internal uint64 key hashes, truncates before checking the integer destination and rounds integer-to-binary32 conversions directly. Source/default/wide native and standalone regression fixtures cover these boundaries.


## Runtime results after the default switch

`runtime-samples-linux-amd64.json` uses the same harness against preparatory head `bd45f92a` and the default32 candidate. Each element is produced by the runtime's numeric Binary operation, retaining its actual boxed dynamic identity. Three fresh processes per case alternate widths; a wide host checksum prevents default overflow. Scalar payloads report `int32`/`float32` in the candidate and `int64`/`float64` in the baseline.

| Case | Elements | Retained heap 64 → 32 | Allocations 64 → 32 | Median construction ms 64 → 32 | Median 10-pass traversal ms 64 → 32 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Boxed Int | 1,000,000 | 24,007,272 → 20,007,304 | 1,000,025 → 1,000,025 | 154.4 → 154.0 | 37.0 → 78.3 |
| Boxed Float | 1,000,000 | 24,007,368 → 20,007,384 | 1,000,026 → 1,000,025 | 100.4 → 89.9 | 30.4 → 75.5 |
| Boxed record | 100,000 | 39,205,784 → 38,405,880 | 500,008 → 500,009 | 170.8 → 184.1 | 60.3 → 136.0 |

The runtime results confirm about 17% retained-heap savings for boxed scalar collections and 2% for map-backed records, with unchanged allocation counts. Representative RSS falls from about 34,200 to 30,000 KiB for scalar collections and 50,500 to 49,400 KiB for records. Typed layout controls still halve four/eight-byte scalar buffers and twelve/twenty-four-byte records; interface slots and object headers remain unchanged.

These measurements do **not** establish a speedup. Traversal includes generic inspection and conversion to the wide host checksum and is slower in the candidate samples; construction is mixed. Shared-host scheduling remains uncontrolled. The runtime Binary harness measures boxing paths; it is not a benchmark of every generated typed expression or collection algorithm.

`factory-samples-linux-amd64.json` separately exercises Integer/Float parsing factories, including a temporary decimal token per element. It saves only about 2.4% of scalar retained heap (32,007,192 → 31,227,656 bytes): short-lived token strings and live scalar boxes share Go's tiny allocator blocks. This further shows why four-byte payloads do not imply a uniform whole-heap reduction. Those construction timings include text parsing and cannot describe ordinary lowered literal or arithmetic speed.


After integration of unrelated #278, the current List header is40 bytes/alignment8 rather than the48-byte historical control: removal of its COW flag is a separate change. Record24/8, Alternative56/8 and interface16/8 remain as measured. The retained-box sample comparisons do not include that unrelated header change.
