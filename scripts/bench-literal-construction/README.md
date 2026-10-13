# Release List literal construction (#147)

This implements both original #147 scopes. Optimized literals over 1,024 elements
use private typed data for complete checked Int/Float/Bool/String constants;
other literals use fresh sized construction and ordered 64-element helpers.
The constructor ABI is supplied by #142, provider #315 at
`8c6569060fd9b073350c7bc2fa665c8fc3ceb189`; no rival storage is implemented here.
Int remains signed 64-bit and Float binary64. Closed #238/#301's boxed-copy
experiments stay closed. Debug #272 is inherited, not rebenchmarked.

Independent before: self-contained ms built from pristine main
`f01d88003284cc21ffda49284b04694c53f8cd8a`, before any candidate checker/lowering
change. Candidate measurement tree: `ab25fda1f50d3c52278c79820deb99025ef1abb9`,
including main `f5b838f483b0a773ac4b67ed498446110e0f8f02` and the actual #142
provider. Go 1.25.1, Linux amd64, AMD EPYC 9V74. Each CLI build forces a neutral
source edit, executes the resulting binary, and records wait4 child peak RSS.
Compilation/linking are excluded from construction benchmarks. Generated Go,
benchmark harnesses and binary/source hashes are retained in `.artifacts/literals-147/`.
The compact executable oracle remains independently frozen under
`pkg/build/testdata/literal-data`; the pre-AST oracle is unchanged.

## Review status

Scalar constants and checker scaling meet the measured gates. The effectful
initializer is held: 2,200 cheap source calls regress construction by about
20–24% (GOGC100 1.243, 95% interval 1.195–1.275; GOGC50 1.202,
1.185–1.216). Same-runtime controls confirm about26% emitter overhead,
so this is not dismissed as a storage-provider difference. All samples are in
`results/runtime-calls*.jsonl`. InitListInt is not inlineable (cost118/budget80);
the profile attributes8.6% cumulative CPU to it. Parent/runtime coordination
is assessing strict inlineable initialization or a distinct owned-slice seam.
No regressing effectful path is approved for merge; this report will be updated
when the actual provider mitigation is measured.

## Results

Three alternating forced-edit Release build pairs, warmed dependencies:

| Int elements | Before → after wall | Before → after peak RSS | Before → after executable |
| --- | --- | --- | --- |
| 16,000 | 1.382 → 0.254 s | 315,348 → 137,004 KiB | 6,217,876 → 5,783,700 B |
| 100,000 | 10.397 → 0.610 s | 1,797,264 → 233,836 KiB | 9,674,900 → 6,455,444 B |

Construction uses two allocations in both forms. 16K B/op falls
262,192 → 131,216; 100K falls 1,605,680 → 802,960. Twelve randomized paired
400ms samples per size/GC target, CPU0 for 16K and CPU1 for 100K,
GOMAXPROCS=1, normal unprofiled runtime:

| Elements / GOGC | After/before geometric ratio | Paired bootstrap 95% interval |
| --- | --- | --- |
| 16K / 100 | 0.361 | 0.293–0.443 |
| 16K / 50 | 0.239 | 0.176–0.317 |
| 100K / 100 | 0.099 | 0.079–0.124 |
| 100K / 50 | 0.080 | 0.054–0.113 |

These shared-host measurements favor construction and avoid the rejected
~1.6x boxed-copy slowdown. They compare the complete generated constructor and
actual runtime, not a synthetic storage control. Other tests/builds ran on this
shared host; timing variability and paired intervals remain explicit. Raw
samples are committed in `results/`. Effectful-call build and construction
controls use 2,200 source calls; the 16K AST test separately enforces helper
order/bounds. Native regressions exercise defaults, generics, nested/mutable
aliases, growth, strict Result slicing, scalar signed zero, return/try/loop
exits and cleanup.

## Reproduce

Use two independently built, self-contained ms binaries and writable caches.
The inherited Debug drivers are reused with an explicit Release option:

```sh
MANUSCRIPT_CACHE_DIR=/tmp/literal-cache python3 scripts/bench-debug-literals/cli_pairs.py --baseline /path/before/ms --prototype /path/after/ms --output .artifacts/literal-pairs --sizes 16000,100000 --count 3 --build-type Release
python3 scripts/bench-debug-literals/extract_runtime.py --cache /tmp/literal-cache --output .artifacts/literal-pairs --sizes 16000,100000 --go /path/pinned/go --repo /path/before --build-type Release --variants baseline
python3 scripts/bench-debug-literals/extract_runtime.py --cache /tmp/literal-cache --output .artifacts/literal-pairs --sizes 16000,100000 --go /path/pinned/go --repo /path/after --build-type Release --variants prototype
python3 scripts/bench-debug-literals/runtime_pairs.py --binary baseline=/path/before.test --binary typed=/path/after.test --cpu 0 --gc 100,50 --count 12 --benchtime 400ms
```

Add `--elements calls` to build/extraction drivers for the effectful control;
the exact actual-call wrapper remains in the generated source. Extraction checks
all values and fresh backing through public runtime operations, so it serves
both representations without reading private storage fields. Archive original
sources and SHA256 hashes before rebuilding. No native build uses system Go.
