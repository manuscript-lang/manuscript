# Cranelift backend spike

Throwaway spike answering three questions before any rewrite: can a real compiler for the proposed no-GC value semantics produce the speed that hand-written C showed (`bench/perf/kernels/c/ms.c`), are Cranelift dev builds as fast to produce as `ms build`, and what breaks. It is not part of the toolchain and nothing depends on it.

## What it is

- `msc/`: a Rust compiler (~2.6k lines) for a Manuscript subset: records, alternatives, `match`, `while`, `if`, `let`/`mut`, `List[T]`, `Map[Int, Int]`, `Optional[Int]`. Parses, type checks, enforces the ownership rules, lowers straight to Cranelift 0.136, writes an object file, and links with `cc -fuse-ld=lld`.
- `msrt/`: the runtime as a `no_std` Rust static library over libc (faults, allocation, the ordered Int map, clock, cancellation flag).
- `kernels/main.ms`: the seven `bench/perf/kernels` programs rewritten for value semantics (`mut` instead of `var`, index-per-access in `nbody`).
- `bench.sh`: builds and runs Go, Manuscript on the Go backend, the hand-written C, and two `msc` builds, interleaved.

Semantics implemented, as proposed: values have one owner and move at last use into consuming positions; parameters borrow; `mut` parameters are marked at the call and compiled as copy-in/copy-out (equivalent to a reference under exclusivity, and keeps values in registers); a `mut` argument may not overlap another argument; droppable locals carry drop flags; temporaries die at the end of their statement; Int arithmetic is overflow-checked, list indexing bounds-checked, and every loop polls an atomic cancellation flag. Values are flattened into scalar SSA variables (a list is three registers), and small non-recursive functions are inlined with Cranelift's inlining hook.

Checked by hand: use after move (including across loop iterations), mutation through `let`, a missing call-site `mut`, overlapping `mut` arguments, and moving out of an element all fail to compile with a direct message; overflow and out-of-range indexing fault at run time; a drop-heavy program (trees, nested lists, reassignment, early return from a loop, temporaries, maps) is clean under valgrind with every allocation freed.

## Results

Linux amd64, Xeon 2.1 GHz, four vCPUs, 2026-10-19. Reproduce with `sh experiments/cranelift-spike/bench.sh 9` (needs `make build`, clang, cargo).

Run time, min of 9, microseconds and ratio to hand-written Go:

| kernel | Go | Manuscript today (Go backend) | C, Manuscript semantics (clang -O2) | msc (Cranelift) | msc, no checks or polls |
|---|---:|---:|---:|---:|---:|
| sieve_5M | 62560 | 1.66x | 0.50x | 0.57x | 0.57x |
| nbody_200k | 10545 | 1.03x | 0.93x | 1.18x | 1.05x |
| life_128x128_50 | 57373 | 1.39x | 0.56x | 0.66x | 0.40x |
| matmul_200 | 12261 | 1.88x | 0.57x | 1.37x | 0.75x |
| trees_d16_x20 | 43430 | 1.73x | 0.79x | 0.95x | 0.93x |
| collatz_1M | 311199 | 1.47x | 0.92x | 1.85x | 1.39x |
| map_count_2M | 25810 | 1.37x | 0.63x | 1.39x | 1.20x |

Build time for the same 240-line program, wall clock:

| build | time |
|---|---:|
| `msc` total (parse 0.4 ms, check 0.2 ms, Cranelift 14 ms, link 30 ms) | 45 ms |
| `cc` driver linking an empty C program, for reference | 26 ms |
| `ms check` | 46 ms |
| `ms build` after a source edit | 640 ms |
| `ms build` with unchanged source (cached) | 175 ms |
| `clang -O0` / `-O2` of the equivalent C | 179 / 261 ms |

## Findings

- The semantics compile to fast code with a straightforward compiler: no MIR, no borrow inference, one pass over the checked tree. The ownership rules took ~600 lines of checking and gave clear errors.
- Cranelift dev builds beat today's Manuscript on four kernels (sieve 2.9x, life 2.1x, trees 1.8x, matmul 1.4x), tie on map_count, and lose on nbody (1.15x slower) and collatz (1.26x slower). Against clang on the same semantics they are 1.15x–2.4x slower. That is the expected dev-tier gap: release builds need LLVM to reach the C numbers.
- Builds are 14x faster than `ms build` after an edit. Code generation is 14 ms; most of the rest is the `cc` driver. Calling the linker directly with a prebuilt runtime archive is the next saving.
- Cranelift's weaker spots showed up exactly where the run times lag: no strength reduction of `x % 2 == 0` to a bit test (collatz), overflow flags materialized with `seto`/`test`/`jne` instead of `jo`, no loop rotation, and repeated bounds checks without range analysis (matmul 1.8x from checks). Range analysis and these peepholes belong in our own mid-level pass, not Cranelift.
- Two correctness traps found:
  - A plain load of the cancellation flag was hoisted out of loops by Cranelift's LICM, which silently disables cancellation. The poll must be an atomic load.
  - Cranelift 0.136's inliner (`create_global_values` in `inline.rs`) copies symbol global values without remapping their external-name reference, so an inlined callee's symbol resolves to whatever the caller's table holds at that index (here `msrt_now_us` instead of `msrt_cancelled`). Worked around by declaring the poll symbol first in every function and not inlining callees with other symbols. Worth reporting upstream.
- A Rust `std` runtime made the static library 22 MB and linking 110 ms; `no_std` over libc brought linking to 30 ms. Runtime crates for TLS, HTTP, and compression will need the same care (prebuilt, trimmed, or dynamically linked in dev builds).

## Not covered

DWARF debug info (Cranelift emits none itself; line tables need `gimli`), strings beyond literals, closures, generics in user functions, interfaces, concurrency, I/O, `.copy()`, and a release backend. The C numbers stand in for an LLVM release build; nothing here measures one.
