# Compile-time stress

Generated programs that push one dimension of the compiler (statements in one function, nesting depth, generic calls, branches). `python3 gen_shapes.py <kind> <n> > t.ms` and `python3 gen_flat.py <kind> <n> > t.ms` print the program; time it with `MS_CACHE=off MS_TIMINGS=1 ms build t.ms -o t` (phase times on stderr). Both programs also run: each prints one number.

## 2026-11-14

`ad2dae25` plus the change below, 4 vCPU Xeon VM, `ms build` (Release, LLVM). Wall time of `ms build`.

| shape | n | before | after |
|---|---:|---:|---:|
| `manyinst`: `n` statements calling a generic function in one `main` | 200 | 1.1 s | 0.3 s |
| | 400 | 6.8 s | 0.2 s (codegen) |
| | 800 | 80 s | 0.4 s (codegen) |
| | 2000 | not run | 1.1 s (codegen) |

Cause: the optimizer folds the branches of a long straight-line `main` into one basic block of thousands of instructions, and LLVM's instruction selection is superlinear in one block (98% of `llc` time; 300 statements took 2.3 s, with the same function marked `optnone` 60 ms). A function over 8000 IR lines with no loop now skips the optimizer like the existing 60000-line bound; no function of the benchmark suites changes.

Open (not fixed here):

| shape | n | time | note |
|---|---:|---:|---|
| `generic`: `Box(Box(...(1)))` | 120, 240 | 0.4 s, 3.2 s | cubic: the ownership classifier compares each type with its ancestors (`same_instance`) once per call and level |
| `nestfor`: `n` nested `for` loops | 500, 900 | 8.7 s, 47 s | cubic in depth |
| `elseif`: `n`-arm `else if` chain | 5000, 20000 | 1.0 s, 6.3 s | quadratic |
| `record` / `enum` with `n` fields or cases | 20000 | 3 s | quadratic |

Nesting deeper than 1000 levels and expression chains over 10000 operators stop with a parse diagnostic, not a crash; no input in this sweep crashed the compiler.
