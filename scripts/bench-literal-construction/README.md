# Release List literal construction (#147)

This implements both original #147 scopes. Optimized literals over 1,024 elements
use private typed data for complete checked Int/Float/Bool/String constants;
other literals use fresh sized construction and ordered 64-element helpers.
The constructor ABI is supplied by #142, provider #315; no rival storage is
implemented here. The latest integration uses strict initializers at
`bea5c048ebf261eaa6d9ca6937c9aefc250ec75f` and current main's IR route.
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

The joint effectful path meets the gate. It consumes #87's published native
scalar boundary for deferred primitive operands; no expanded storage ABI is
needed. The independently published #326 remains draft until the parent selects
the dependency integration order and exact-head required checks finish.

Scalar constants and checker scaling meet the measured gates. The effectful
initializer without #87 remains held. The first 2,200 cheap-call control regressed by
20–24%; same-runtime controls confirmed about 26% emitter overhead. Strict
typed setters preserve state/kind/bounds safety and inline at cost 31 instead
of 118, but the actual IR integration `e9169b56a6cc9c29fcd0de817290e35105fa5775`
still regresses: GOGC100 ratio 1.269, paired 95% interval 1.236–1.314; GOGC50
1.240, 1.214–1.263. Every pair is slower. Both forms allocate twice; B/op falls
41,008→18,576. Twelve randomized 400ms pairs per GC use the independent original
main baseline. Raw samples and exact source/binary hashes are in
`results/runtime-calls-strict*.jsonl` and `results/strict-provenance.json`.

An artifact-only control fills a fresh typed slice with ordered assignments,
then uses the existing fresh-copy `NewIntList`. At 2,200 cells Go puts this input
on the stack, retaining two heap allocations. It reduces the regression to
GOGC100 1.105[1.081,1.135] and GOGC50 1.102[1.074,1.130], but remains slower.
This control is not production lowering and does not establish 100K allocation
parity. Parent coordination will test #87's actual native-consuming/direct-call
path before approving a larger constructor seam. This rejected control is not
promoted.

The joint control now uses #87 at
`92a73898110396a9457bc1244222c4319eb16614` and #147's native-consuming adapter
at `b81323ae`. Against the #87-only boxed literal emitter, twelve randomized
400ms pairs per GC give GOGC100 ratio 0.707[0.697,0.718] and
GOGC50 0.649[0.624,0.692]. Both forms retain two allocations;
B/op 41,104→18,576. The same written calls and source checkpoints are retained.
`g.scalarValueAs` selects the authoritative typed call context for deferred
IR operands, including calls whose boxed adapter cannot share the native body.
Literal source order and the 64-element helper bound remain unchanged.
Raw paired rows, generated-source hashes and exact consumer/runtime heads are
in `results/runtime-joint-calls*.jsonl` and `results/joint-provenance.json`.

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

Current IR/strict-provider rerun at `e9169b56` retains these gains. Three forced
edit pairs give 16K median 1.471→0.278s, peak RSS 320,964→136,684KiB and
binary 6,217,876→5,787,796B; 100K 10.616→0.629s,
RSS 1,879,428→226,476KiB and binary 9,674,900→6,459,540B. Construction still
uses two allocations with the same B/op reductions. Twelve randomized 400ms
pairs per GC give ratios 0.321[0.309,0.333] / 0.236[0.230,0.243] for 16K and
0.118[0.113,0.124] / 0.166[0.162,0.170] for 100K at GOGC100 /50 respectively.
Raw build/runtime rows are `results/ir-builds.jsonl` and
`results/runtime-ir-*.jsonl`; hashes are in `strict-provenance.json`.

Called native regressions also verify already-canceled admission, cancellation
after the 65th effect (a later body never mutates), and exact operator/caller/main
source frames for a fault beyond a helper boundary. These tests pass on the
current IR/provider integration; generated helper frames do not leak.

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
