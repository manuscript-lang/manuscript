The current copy implementation is held for review. Its compiler and memory
improvements are substantial, but repeated construction has a confirmed cost on
this host. Recommend **not merging the current scalar-copy optimization under
the stated runtime-performance priority**. The separate #142 typed-storage work
may offer a representation that avoids the interface-array copy barrier; that
is a proposal to measure, not an asserted fix. The effectful-element chunking
scope can be reviewed separately without treating scalar runtime cost as noise.

The implementation remains at PR #238 head
`63b30c6a948bf4664c39bb736bfd40fffea422ef`; its CI and all twelve distribution
build/verify jobs passed. `make verify`, all Go/native tests, compiler race and
offline distribution checks passed. Combined-main literal/oracle/fault-frame
tests also passed against `93fcb4fe`. Merge is explicitly paused for parent review.

## Runtime evidence

Go 1.25.1, Linux amd64 AMD EPYC 9V74, cpuset 0–4, quota four CPUs. Compile and
process startup are excluded. Binaries retain the same source-call wrapper and
runtime including #218. A fixed seed randomizes variant order within each pair.
For 16,000 elements, CPU 0 and GOMAXPROCS=1; twelve pairs per GC setting, 400 ms
per trial. With GC disabled, use bounded 200-iteration trials to avoid unbounded
memory. The larger case uses CPUs 0,1 and GOMAXPROCS=2, ten pairs, 500 ms trials.
Ratios are geometric means of within-pair ratios; intervals are percentile
bootstraps of paired log ratios (10,000 resamples). They describe this host and
workload, not a universal application slowdown.

| Case | Current/baseline ratio | 95% paired interval | Slower in every pair |
| --- | ---: | ---: | --- |
| 16,000, GC 100 | 1.509 | 1.444–1.589 | yes |
| 16,000, GC 50 | 1.654 | 1.496–1.883 | yes |
| 16,000, GC off | 1.088 | 0.916–1.327 | no |
| 100,000, GC 100, two CPUs | 1.623 | 1.511–1.761 | yes |

The original five unpinned pairs had overlapping ranges and did not establish a
regression alone. These additional measurements consistently show a cost with
normal GC. Both forms still allocate two objects with the same per-evaluation
bytes. Profiled timings are not used in the comparisons.

CPU profiles put `runtime.bulkBarrierPreWrite` at about 40% cumulative in the
copy path. Scanning, pointer lookup and write-barrier work are prominent. GC-off
samples are noisier but weaken the cost. This supports a GC/write-barrier cause;
it does not isolate global-root scanning as the sole mechanism. Bundled Go's
`runtime/slice.go`, `runtime/mbarrier.go` and compiler `walk/order.go` were read
when constructing the mitigation experiments. Production uses no unsafe code
or runtime-internal calls.

## Safe mitigation results

All variants retain fresh storage. Default-GC paired ratios at 16,000 elements:

| Variant | Ratio versus baseline | 95% interval |
| --- | ---: | ---: |
| append to a fresh slice | 1.521 | 1.446–1.605 |
| fresh fixed array, then copy | 1.335 | 1.296–1.373 |
| copy array by value, return its slice | 1.256 | 1.225–1.289 |
| named source slice, make+copy | 1.544 | 1.429–1.675 |
| non-inlined clone helper | 1.478 | 1.341–1.650 |
| direct constant assignments, 64/256/1024 chunks | 3.35–3.72 | all above equality |

The fixed-array variants reduce the cost but leave a consistent increase.
Direct assignments also weaken build/RSS/binary results: 100,000 elements at
256 assignments compiled in 11.9 s / 1,818,812 KiB with a 13,934,776-byte
binary. Typed conversion was already rejected for per-element boxing. Local
literal copies were also slower in a smoke check; that check is not a matched
source-wrapper comparison and is not used for confidence claims. No tested
mitigation removes the runtime cost while retaining the copy path's build gains.

## Reproduce and retain evidence

Use `main.go` to emit independent baseline/current workloads. Build benchmark
binaries with the bundled SDK's `go test -c -mod=vendor -tags=ms_lean`. Then run:

```sh
python scripts/bench-flat-literals/runtime_pairs.py --binary baseline=/absolute/before.test --binary copy=/absolute/after.test
python scripts/bench-flat-literals/runtime_pairs.py --binary baseline=/absolute/before100k.test --binary copy=/absolute/after100k.test --cpu=0,1 --gomaxprocs=2 --gc=100 --count=10 --benchtime=500ms
```

The committed `results/` contains raw paired samples. Generated variants,
profiles, build measurements and failed-harness logs remain under
`.artifacts/flat-literals/tradeoff/`. Original logs are retained; a missing `-2`
benchmark-name regex interrupted one larger-case run and was corrected before
the reported ten pairs. Production files and both independent oracles remain
unchanged during these experiments.
