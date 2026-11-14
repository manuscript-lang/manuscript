# Compile time and binary size at scale, 2026-11-14

Release `ms` from `make build` (`88287373`), rustc 1.99.1, Go 1.24.7, 4 vCPU Xeon VM, one run each. `functions.py N` writes the same N-function program for Manuscript, Rust and Go (a map, a record, a string interpolation, a list and a branch per function, 13 lines in Manuscript); `shapes.py KIND N` writes single-feature stress programs; `run.sh N...` times every toolchain.

## Whole programs, N functions (about 13 lines each)

| N | ms Release (LLVM) | ms Cranelift | ms Debug | Go | rustc -O | rustc debug |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 4.5 s | 0.8 s | 0.5 s | 6.5 s | 43 s | 2.3 s |
| 2000 | 18 s | 3.6 s | 1.8 s | - | - | - |
| 8000 | 68 s | 9 to 13 s | 7.5 s | 8.1 s | - | - |
| 32000 | - | 51 s | 28 s | 40 s | - | - |

Binary size at 500 functions: ms Release 1.9 MB, Cranelift 2.4 MB, Debug 2.4 MB, Go 2.7 MB, rustc -O 5.0 MB, rustc debug 5.8 MB. At 8000: ms Release 20 MB, Cranelift 28 MB, MinSizeRel 21 MB, Go 10.6 MB. Hello world: ms 691 KB in 0.13 s, Go 2.2 MB in 0.16 s, rustc -O 4.4 MB in 0.13 s.

Every column grows linearly from 500 to 32000 functions (`ms check` alone: 0.78 s, 3.1 s, 12 s at 2000, 8000, 32000). Cranelift and Debug builds match Go's speed; Release (LLVM) costs about 8 ms per function against Go's 1 ms but is far ahead of `rustc -O`, and a program of ordinary size builds in under 0.4 s. Per function, ms Release code is about 2.3 KB against Go's 1.0 KB; both are small next to Rust.

## One-feature stress programs, 2000 and 8000 items (Cranelift / Release)

One 8000-statement function 3.5 s / 3.7 s; a 8000-arm `match` on `Int` 0.8 s / 1.7 s; an 8000-variant enum and match 0.7 s / 3.6 s; an 8000-link `else if` chain 1.2 s / 2.2 s; 8000 types 0.5 s; a 4000-piece `+` chain 0.4 s / 1.0 s; an 8000-deep call chain 1.1 s / 1.9 s; 8000 locals 0.3 s / 0.4 s; a literal list of 8000 items and a map literal of 8000 entries 0.2 s. All are linear in N. A `+` chain over 10000 operators is rejected by the parser with a clear message.

## Result

No superlinear growth and no case over 1.5x Go's time or size on the Cranelift path found. The only notable cost is Release at very large size (8 ms per function), already split across units ([wiki](../../../wiki/benchmarks-and-performance/release-llvm-builds-split-into-parallel-units.md)); nothing was changed.
