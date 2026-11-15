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

The instruction counts do not move, so the variables stay on for every build and are not gated on the debug
build type. The compile cost is the one number that moved; the whole-program build times in the table are not
comparable because the second build of each program reuses cached unit objects.

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
