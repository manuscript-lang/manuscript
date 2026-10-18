# Bounded Debug literal prototype (#147)

This draft changes only Debug lowering for complete flat lists with more than
1,024 immutable scalar literal elements. No mutable source List is global:
private scalar data is copied by `append([]rt.Value(nil), data[:]...)` into fresh
storage on every evaluation. Effects, names, conversions, mutable/nested values,
Decimal and unary numeric expressions keep existing lowering. There is no
chunking, runtime ABI change, unsafe code, or new numeric-width assumption.
Numeric expressions use checked ordinary expression lowering; signed zero and
rounded-underflow cases stay on that path. Current evidence uses existing
**Int64/Float64**, before the separate #271 Int32/Float32 migration.

**Review hold:** this prototype is not approved for merging. Release #238 also
remains held: its constant-table copy repeatedly slowed construction under GC.
This Debug prototype improves builds and default-GC construction, but also has
a confirmed construction regression at GOGC=50 and fixed live global data,
even when literal functions never execute. #147 remains open: Release,
effectful/mixed lists, other excluded constants and nested-depth scope remain.

## Build-mode design and compatibility

`Options.BuildType` selects the build kind before lowering.
The CLI passes its selected kind through this additive API and lowers once.
`CompileSource`/`CompileFile` keep ordinary default Go. Their existing
`BuildChecked(result, ..., true)` flow stays valid and uses ordinary lowering;
legacy callers do not automatically gain the Debug list optimization.
`Result` keeps all six original fields in the original order, including external
unkeyed struct-literal compatibility. No Options field, prepared wrapper,
retained recipe, global side table, or additional checked-program lifetime is
introduced. Builders always use the caller's supplied Source; edits and manual
results need no provenance guard. Cache identity uses supplied source plus
the existing build-mode/source-root keys. Match the explicit compile and build
kinds when selecting a representation.

The external compatibility fixture is
`pkg/build/testdata/debug-literals/result-compatible.go`, compiled with the
bundled SDK. Native tests cover edits to both legacy and Debug-generated Source.

CLI path selection is explicit:

| Path | Default lowering/native kind | Debug selection |
| --- | --- | --- |
| build/run/test, including run/test --watch | Release | --debug or --build-type Debug |
| debug | Debug | Always; conflicting kinds rejected |
| profile | RelWithDebInfo | Explicit --build-type Debug |
| VS Code source launch | Debug | Adapter invokes `ms build --debug` |
| dap attach/launch of existing executable | Existing artifact | No compilation |
| emit | Ordinary Release source | Build-kind flags rejected |
| check/lint/inspect/diagram/lock/doc | Source analysis | No Go generation |
| Legacy CompileSource/File -> BuildChecked(Debug) | Ordinary representation, Debug native flags | Correct semantics without this optimization |

Thus default build/run/test/watch and default profiles do not incur the Debug
table's fixed rooted data or construction tradeoff.

Debug copy remains a single expression on the source statement. A copy IIFE
caused false source breakpoint/step frames; generated-file directives inside it
still introduced extra frames. Native DAP tests compare the unchanged compiler
and the prototype, check both evaluations, locals, watches and source stops.
Existing bookkeeping-line coalescing and first-page list rendering are tested
without changing adapter behavior.

## Independent provenance

The independent before checkout is main **bee671d4531fb26d8c2445e3c477ff4a2a0eedf6**,
with its unchanged compiler, real bundled payload, and Go **1.25.1**. The before
and prototype executables were separately built using that bundled SDK. Existing
pre-AST golden fixtures were not changed. The new Release oracle in
TestDebugLiteralBuildRecipe was captured by running the unchanged before
compiler, never generated from the candidate:

- source filename: `literal.ms`, source: `debugLiteralSource()` in the new test
- source SHA256: `db188e2ca7089e9e1146c33a22937174a0d0750843191948e094a64de2371319`
- generated Go SHA256: `c2086ef7502812b744c8db896855f9b0333bb8c210276db43334f7e241de356c`
- first List constructor, go/format.Node SHA256: `14f056a0e496cbba6ff77959a189419ceed5206a63a9ece9b49aa07aae677362`

Superseded by #147: optimized builds now lower this literal to a typed
`rt.ListTable`, so the test asserts that shape instead of this hash. The hashes
remain as the record of the original baseline.

The enforced oracle hashed the constructor independently of stdlib registration
updates on main. It was separately captured by parsing the unchanged before
compiler's generated Go and formatting that List composite with the bundled
Go AST formatter. This keeps unrelated stdlib API additions from requiring a
baseline refresh. The complete original source hashes above remain retained.

Both independent pipelines generated byte-identical default Go for all 82
acceptance fixtures compiled with Options{Tests:true}. Retained ordered hashes:
[release-corpus.txt](results/release-corpus.txt), SHA256
`cd9c05f70cff1e03b3fbde6bdc1aa604432431cea2d26c40ea8630743269d3fe`.
Those hashes represent the original main snapshot, not future width migrations.

## Current matched-main evidence after API review

The additive API candidate and independent unchanged before executable both use
main **9391cb9b0102c6cc9b7c7a0b619a984c78dd92e3**, including the canonical docs
repair. They share the same runtime workspace identity
`92353d7e21c30f05c2575b591347d8d1`; this removes stdlib/runtime changes as a
comparison confound. The API selects Debug before one lowering pass.
All **86** current acceptance fixtures compiled with Options{Tests:true} have
byte-identical default Go on both pipelines. The independent ordered corpus
[current-release-corpus.txt](results/current-release-corpus.txt) has SHA256
`89007ddfb2c60b9691dbb66d7d8b3d7de8e280cda3c393d0bd712e4a9e5cef3e`.
The earlier 82-fixture corpus and original constructor oracle remain frozen.

Whole-CLI Debug builds: three alternating forced-edit pairs, warm SDK/workspace,
CPU affinity 2,3, bundled Go1.25.1, current Int64/Float64 semantics. Build wall
includes checking and one selected lowering pass. RSS is wait4 child peak KiB,
not retained heap. This compiler/CLI workload exceeds the small-child inherited
RSS floor discussed below. Native output was executed after each build.
All [current samples](results/current-cli-builds.jsonl) are retained. The 1,024
control has identical binary size and constructor code; timing differences
reflect host noise. Compilation RSS is visibly nonmonotonic for unoptimized Go.

| Elements | Median before → prototype | Build RSS median (MiB) | Debug executable bytes |
| --- | --- | --- | --- |
| 1,024 control | 0.542 → 0.451 s | 118.0 → 118.0 | 11,300,447 → 11,300,447 |
| 1,025 | 0.537 → 0.328 s | 124.6 → 116.3 | 11,300,439 → 11,242,862 |
| 4,000 | 2.597 → 0.354 s | 847.1 → 121.5 | 11,542,067 → 11,312,494 |
| 16,000 | 2.254 → 0.514 s | 269.3 → 133.3 | 12,512,885 → 11,603,310 |
| 100,000 | 14.303 → 1.659 s | 1,693.0 → 253.3 | 19,308,159 → 13,618,550 |

Current repeated Debug construction uses actual captured CLI Go, matching
runtime, CPU1/GOMAXPROCS1, **24 randomized pairs at1s/sample** per GC setting.
The [raw pairs](results/current-runtime-100000.jsonl) and
[summary](results/current-runtime-summary.jsonl) use the same paired-log
bootstrap method described below. At100K: GOGC100 **0.817 [95%CI0.737,0.876]**;
GOGC50 **1.220 [1.171,1.271]**. Both allocate2 objects/1,605,680 bytes. The lower
GC target still gives a confirmed ~22% slowdown, consistent with the earlier
~24% result; the earlier result is retained, not erased by this rerun.

### Startup, never-called literals and retained storage

[memory_controls.py](memory_controls.py) captures actual CLI-generated Go and
builds each harness against its corresponding runtime workspace with Debug
flags. Fresh processes, randomized pairs (seed147), CPU0/GOMAXPROCS1, five pairs
per case at GOGC100/50. Four **distinct**100K Int64 literals test fixed global
cost; four4K unique String literals additionally cover string backing. Source
main calls none of the constructors. Harness paths remain reachable at link
time and select zero, one, or64 calls **per literal** at runtime. The last result
from each constructor remains live. Two forced GCs release transient buffers
before retained readings. Startup readings occur before source initialization;
process wall includes initialization, workload and forced GCs, so zero-call wall
is a controlled startup/GC probe rather than natural application startup latency.

Go HeapAlloc excludes static globals. Direct child `/proc/self/status` VmRSS,
VmHWM, RssFile and RssAnon measure the executable image; Linux wait4 can retain
an inherited pre-exec parent/taskset RSS floor even with posix_spawn, so raw
wait4 peak values are recorded **but excluded from memory conclusions**. Every
raw heap/RSS sample is retained:
[Int controls](results/current-memory-int4.jsonl),
[String controls](results/current-memory-string4.jsonl).

| Four Int64 literals | GOGC | Retained RSS before → prototype (MiB) | Retained heap (MiB), both | Process wall median before → prototype |
| --- | --- | --- | --- | --- |
| Zero calls | 100 | 11.00 → 15.54 | 0.42 | 8.60 → 21.74 ms |
| One call each | 100 | 42.40 → 21.91 | 6.54 | 37.64 → 57.29 ms |
| 64 calls each | 100 | 46.67 → 24.54 | 6.54 | 1008.01 → 705.76 ms |
| Zero calls | 50 | 11.00 → 15.54 | 0.42 | 7.98 → 23.14 ms |
| One call each | 50 | 42.51 → 21.91 | 6.54 | 48.64 → 51.87 ms |
| 64 calls each | 50 | 43.20 → 22.75 | 6.54 | 1289.99 → 1102.34 ms |

Initial startup VmRSS was9.36→8.95MiB at zero calls, before forced scanning
made the rooted table pages resident. This **does not remove the fixed cost**:
post-GC zero-call RSS rises by~4.54MiB despite identical heap. ELF sections show
`.data` increases by**6,400,016 bytes**, approximately4×100K×16 for the interface
tables. `.noptrdata` grows3,200,000 bytes while `.rodata` shrinks3,332,128 bytes;
scalar backing changes section rather than representing an entirely new pool.
The after-call RSS win includes fewer executable code pages: `.text` shrinks
from31,880,913 to4,453,617 bytes. Static payloads remain live regardless of calls.
[Exact Int ELF sections](results/current-elf-int4.json) are retained.

| Four String literals | GOGC | Retained RSS before → prototype (MiB) | Retained heap before → prototype (MiB) |
| --- | --- | --- | --- |
| Zero calls | 100 | 9.61 → 9.71 | 0.42 → 0.42 |
| One call each | 100 | 13.75 → 10.06 | 1.16 → 0.67 |
| 64 calls each | 100 | 15.59 → 10.65 | 1.16 → 0.67 |
| Zero calls | 50 | 9.62 → 9.71 | 0.42 → 0.42 |
| One call each | 50 | 13.73 → 10.06 | 1.16 → 0.67 |
| 64 calls each | 50 | 15.27 → 11.40 | 1.16 → 0.67 |

String `.data` grows**512,016 bytes**:16K interface entries plus static string
headers. String byte backing remains in `.rodata`; the much larger before
`.rodata` also includes function stack metadata. Both natural startup readings
were~8.9MiB. Full [String ELF sections](results/current-elf-string4.json) separate
segments; heap improvement after calls does not imply the global data is free.
Multiple roots alter GC pacing (e.g. at Int64/GOGC50/64 calls,89→54 GC cycles),
so this four-table workload is not a substitute for the single-table benchmark
that confirms the construction regression.

Reproduce using independent before/candidate executables and the bundled SDK:

```sh
python bench/debug-literals/memory_controls.py \
  --baseline /path/to/main/ms --prototype /path/to/candidate/ms \
  --go "$PWD/toolchain/go/bin/go" --cache "$MANUSCRIPT_CACHE_DIR" \
  --output "$PWD/.artifacts/memory-int4" --elements 100000 --literals 4
python bench/debug-literals/memory_controls.py \
  --baseline /path/to/main/ms --prototype /path/to/candidate/ms \
  --go "$PWD/toolchain/go/bin/go" --cache "$MANUSCRIPT_CACHE_DIR" \
  --output "$PWD/.artifacts/memory-string4" --kind String --elements 4000 --literals 4
```

## Historical forced-edit whole-CLI Debug builds

The following frozen measurements used the earlier recipe-based prototype
before API review, including default lowering followed by Debug re-lowering.
They establish history, not current API costs. The retained source references
and current matched-main evidence above are authoritative for the revised API.


Linux amd64, warm bundled SDK/native workspace, three alternating-order pairs.
Every build appends a comment to invalidate executable restoration. Build wall
time includes checking, default lowering and Debug re-lowering; RSS is Linux
wait4 peak child RSS (KiB), not retained heap. Binary sizes include Debug DWARF.
Raw [build samples](results/cli-builds.jsonl) and
[cutoff samples](results/threshold-builds.jsonl) include all runs. Cutoff runs
used CPU affinity 2,3. Host contention causes visible variability; the unchanged
1,024-element control has identical generated code and binary size, so its wall
time difference must not be called a speedup. RSS is nonmonotonic in this
unoptimized Go workload and includes compilation/linking children.

| Elements | Median before → Debug prototype | Peak RSS median (MiB) | Executable bytes |
| --- | --- | --- | --- |
| 1,024 (unchanged control) | 0.757 → 0.596 s | 120.7 → 118.0 | 11,194,644 → 11,194,644 |
| 1,025 | 0.580 → 0.415 s | 115.8 → 112.7 | 11,194,644 → 11,137,095 |
| 4,000 | 2.717 → 0.392 s | 847.0 → 119.2 | 11,436,308 → 11,206,727 |
| 16,000 | 2.094 → 0.617 s | 265.8 → 149.0 | 12,407,118 → 11,497,543 |
| 100,000 | 12.873 → 2.361 s | 1,537.9 → 380.8 | 19,198,304 → 13,512,783 |

The measured 1,025-element improvement supports keeping the conservative
1,024-element cutoff. It is a selection cutoff, not a chunk size. This does not
claim the optimal cutoff on every architecture or default-width representation.

## Historical repeated Debug construction

Benchmark Go is captured from actual CLI-generated Debug application cache
entries. Build with `-gcflags=all=-N -l -ldflags=-compressdwarf=false` and
`-tags=ms_lean` using the bundled Go. TestResult checks all elements and independent
storage; only repeated rt.Invoke/constructor work is timed. Initialize happens
outside the timed loop. CPU 0, GOMAXPROCS=1, randomized paired order (seed147),
400ms per sample, 12 pairs at 16,000 and 16 at 100,000. GOGC=off uses bounded 200x
loops. Ratios are prototype/before paired geometric means, with 10,000 paired-log
bootstrap resamples. They describe this host/workload, not all applications.
Both variants allocate **2 objects**, **262,192 B** at 16,000 and **1,605,680 B** at
100,000.

| Elements | GOGC=100 ratio [95% CI] | GOGC=50 | GOGC=off |
| --- | --- | --- | --- |
| 16,000 | 0.566 [0.388, 0.822] | 0.799 [0.658, 0.935] | 0.330 [0.288, 0.383] |
| 100,000 | 0.776 [0.702, 0.865] | 1.068 [0.934, 1.215] | 0.291 [0.258, 0.329] |

A longer 100,000-element confirmation used **24 pairs, 1s per sample** after the
native correctness suite completed. GOGC=100: **0.796 [0.772,0.819]**; GOGC=50:
**1.239 [1.218,1.260]**, every pair slower. The lower GC target thus exposes a
repeatable ~24% Debug runtime cost. Keep that tradeoff visible during review;
private rooted data/copy barriers are not free, even though build time improves.
Raw [16K samples](results/runtime-16000.jsonl),
[100K samples](results/runtime-100000.jsonl), and
[longer confirmation](results/runtime-confirmation-100000.jsonl) are retained.
Release, RelWithDebInfo and MinSizeRel source remain identical to the before
compiler; this prototype changes no Release constructor or runtime ABI.

## Reproduction

Build separate `ms` executables on the before checkout and candidate using each
checkout's bundled toolchain/payload. Keep caches in a writable directory; no
external Go installation is used. From the candidate checkout:

```sh
export MANUSCRIPT_CACHE_DIR=/tmp/ms147-native
python bench/debug-literals/cli_pairs.py \
  --baseline /path/to/before/ms --prototype /path/to/candidate/ms \
  --output "$PWD/.artifacts/debug-literals"
python bench/debug-literals/extract_runtime.py \
  --cache "$MANUSCRIPT_CACHE_DIR" --output "$PWD/.artifacts/debug-literals" \
  --repo "$PWD" --go "$PWD/toolchain/go/bin/go"
python bench/debug-literals/runtime_pairs.py \
  --binary baseline="$PWD/.artifacts/debug-literals/100000/baseline/runtime.test" \
  --binary prototype="$PWD/.artifacts/debug-literals/100000/prototype/runtime.test" \
  --cpu 0 --gc 100,50 --count 24 --benchtime 1s
```

Run make verify, compiler/native conformance, relevant races, and the native
VS Code DAP suite with MANUSCRIPT_MS pointing at the candidate. The new large
literal DAP regression must also run against the independent before executable.
All four build kinds and cache restores, boolean Debug API, caller-edited Source,
fresh storage/default arguments/clones/aliases and exact fault locations have
native regressions. Final-head CI/distributions remain required before any merge,
and parent approval remains a separate gate for this draft.
