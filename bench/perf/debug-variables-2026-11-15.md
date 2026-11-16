# Parameter variables in debug info: cost on the LLVM release backend (2026-11-15)

Question: does describing each named parameter to debuggers (`DILocalVariable` and `llvm.dbg.value`
fragments, `FullDebug` emission, the type nodes repeated per unit) change the generated programs?

Method: the 23 programs of [`suite/`](suite) built with `ms build` (Release, LLVM) twice from the same
revision, once as shipped and once with parameter variables switched off (a temporary local switch in
`describe_params`, not committed). Instruction counts are the `valgrind --tool=callgrind` totals of one run
of each executable on the suite's generated input (scale 1). Intel Xeon 2.10 GHz, 4 cores, Linux x86-64.

| Measure | Result |
| --- | --- |
| Instructions executed | identical to within 0.0011% for all 23 (the largest difference is `pargroup`, a threaded program; 20 of 23 differ by under 0.0001%) |
| Machine code | the normalized disassembly is identical for 20 of 23; `wordfreq`, `pargroup` and `regex` differ in layout only, and their instruction counts match |
| Executable size (includes the DWARF) | mean +0.39%, largest +1.00% (`pargroup`); `strings` +0.00% |
| `llc` plus `opt` time for `tools/llvm-direct/yaml.ms` (5 alternating builds, median) | 2.65 s with variables, 2.54 s without: about +4% |

The instruction counts do not move, but the compile cost (+4%) is over the project's 1% line for debug info, so
LLVM release builds do not emit parameter variables; only Cranelift (debug) builds do. The whole-program build
times of the two builds are not comparable because the second build of each program reuses cached unit objects.

Cranelift debug builds (`--build-type debug`, which emit the variables): 200 builds of eight suite programs with and
without the variables, CPU time per `ms build`: mean 0.140 s with, 0.140 s without, **+0.21%**.

LLVM release builds keep the types alive with the `ms.debug_types` anchor global instead (one constant, no
variables, no live-variable pass): 40 builds of five programs with and without it, CPU time: -1.1% (noise); no
change to the generated code.

Reproduce: build each program as above and compare `callgrind` totals; the per-program table is
`bench/perf/suite/manifest.txt` order.

| Program | Size | Instructions |
| --- | --- | --- |
| interp | +0.20% | +0.00000% |
| graph | +0.39% | +0.00000% |
| objgraph | +0.53% | -0.00000% |
| sim | +0.10% | +0.00000% |
| dispatch | +0.35% | -0.00000% |
| hashing | +0.17% | +0.00000% |
| lz | +0.10% | +0.00000% |
| exprparse | +0.26% | +0.00000% |
| logstats | +0.46% | -0.00000% |
| csvgroup | +0.90% | +0.00001% |
| wordfreq | +0.51% | -0.00000% |
| sortrecords | +0.42% | +0.00000% |
| grep | +0.31% | -0.00001% |
| treegrep | +0.42% | +0.00000% |
| pargroup | +1.00% | -0.00113% |
| jsonsum | +0.90% | +0.00002% |
| dedupe | +0.31% | +0.00000% |
| report | +0.42% | +0.00000% |
| jsonrt | +0.48% | +0.00000% |
| regex | +0.08% | +0.00000% |
| workers | +0.51% | +0.00001% |
| strings | +0.00% | +0.00000% |
| concat | +0.12% | +0.00003% |

## Cranelift debug builds: locals and inlined frames (2026-11-15)

Callgrind instructions of `ms build --build-type debug` (`MS_CACHE=off`) with parameters only (main at `b4258a5a`) against parameters, locals and inlined frames. Same machine as above.

| Program | Before | After | Change |
| --- | --- | --- | --- |
| `bench/perf/suite/interp` | 203,564,706 | 204,313,207 | +0.37% |
| `bench/perf/suite/graph` | 264,451,064 | 266,660,644 | +0.83% |
| `bench/agent/run.ms` (356 lines, pulls in much of the standard library) | 4,051,698,669 | 4,163,301,986 | +2.75% |

The executable of `run.ms` grows from 4,840,944 to 5,173,840 bytes (+6.9%). Most of the added work is writing the larger DWARF (`gimli` location lists and DIEs) and Cranelift's value-label ranges, in proportion to the number of named values and inlined frames, so a program that inlines more standard-library code pays more. Not describing the locals of standard-library functions saved only 0.8 points of the 2.75, so it is not worth a rule. Release (LLVM) builds are unchanged.
