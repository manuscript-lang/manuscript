# Compile time: Manuscript vs Go (2026-10-31)

Machine: 4 cores, Linux. ms built from current checkout (`make build`, release, LLVM tools present). Go 1.x from /usr/local/go.

## Workload (gen.py 40 25 10)
40 directories ("packages") x 25 files, 10 functions + a record/impl per file, cross-file and cross-package imports (acyclic, 3 per file). main reaches every function (an earlier run where only a chain was reachable built in 2s, so ms prunes unreachable code; Go does not). Both programs print the same result (13811947).
- Manuscript: 121,961 lines, 1,000 files. Go: 154,958 lines (braces).

## Results (wall, cold)
| Step | Time |
| --- | --- |
| go build (cold cache) | 10.2 s (21.5 s CPU) |
| go build, 1 file touched | 0.23 s |
| ms check (parse + check) | 1.8 s |
| ms emit (+ lower/MIR) | 2.9 s |
| ms build --build-type Debug (Cranelift) | 10.5 s |
| ms build, Cranelift release (MS_BACKEND=cranelift) | 12.3 s |
| ms build, Release (LLVM) | 293 s (user 279 s: one thread) |

Release LLVM stage, run by hand on the emitted IR (78 MB, 1.93M lines): `opt default<O3>` 146 s, `llc -O3` 91 s, `opt default<O1>` 104 s.

Binary sizes: Go 8.4 MB, ms debug 14.7 MB, ms cranelift 11.2 MB.

## Bottlenecks
1. Release = one monolithic LLVM module through one `opt` and one `llc` process, single-threaded: ~97% of the 293 s. 28x slower than Go cold; Cranelift release is on par with Go (12 s vs 10 s) but single-threaded (Go used 2.1x CPU).
2. No incremental build: `ms build` again recompiles everything (Go's touch-one-file rebuild is 0.23 s). `.ms-cache` caches nothing at object level.
3. Front end is cheap (check 1.8 s, lowering +1.1 s). Debug/Cranelift backend + link ~7.6 s, also single-threaded.

## Proposed fixes (unimplemented)
- Split the LLVM IR into N partitions (by module/SCC, N = cores) and run opt+llc in parallel; expected up to ~4x here. Needs cross-partition inlining care (hot-library helpers are already a separate bitcode).
- Per-function/per-module object cache keyed by content hash (also gives incremental builds), for Cranelift and LLVM.
- Parallelize Cranelift function compilation (functions are independent).
- Size-based fallback: above a threshold, release uses O1 or Cranelift (O1 only saves ~30%, so Cranelift fallback is the real escape hatch).
- Add `MS_TIMINGS=1` per-phase output; none exists today, so phases above are inferred from check/emit/build deltas and the manual opt/llc run.
Caveat: synthetic code; real programs with heavier generics/closures may shift front-end costs.

## Priority
Incremental builds first (per-module/function object cache keyed by content hash), then parallel LLVM partitioning and the rest.

Reproduce: `bench/tools/compile_time.ms` (set `SKIP_LLVM=1` to skip the 5-minute release step).

## Contract-indexed `implements` (2026-11-02)

Workload `gen.py 40 25 10` (122k lines; `@std/io/io.ms` import path), `ms check`, release, base `c30abc7d`, callgrind instruction counts, one machine, diagnostics output byte-identical.

| Build | Ir | wall |
| --- | --- | --- |
| before | 14.45G | 1.9 to 2.6 s |
| `methods_by_contract` index | 8.65G (-40%) | 2.4 s (noisy VM) |

`Checker::implements` was 40% inclusive (32.2M calls, linear scan of all methods). Proposal: `proposals/checker-type-interning.md`.

## Parallel LLVM units (2026-11-03)

Base `a460b7ef`, 4-core Linux VM, `ms build --build-type Release`, cold `.ms-cache`, one run each (noisy VM). Workload `bench/tools/compile_time.ms` with `40 25 10` (122k lines) and `6 25 10` (18.6k lines).

| Workload | before | after | 
| --- | --- | --- |
| 122k lines | 350 s | 60 s (user 157 s) |
| 18.6k lines | 16.9 s | 6.4 s |

Same program output. `opt -time-trace` on the 122k-line IR (142 s of `opt`) showed `ms_entry`, a 33k-line generated `main`, taking 60 s alone, so the serial part now bounds the large case. Programs under 2 MiB of function text per unit are unchanged. See `wiki/benchmarks-and-performance/release-llvm-builds-split-into-parallel-units.md`.
