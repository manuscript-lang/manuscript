# Structural gaps against C

Programs where the generated code does structurally more work than the C twin. `grid.ms` is LCS over a 2001 x 2001 `List[List[Int]]`; `c/grid.c` is the same algorithm (`gcc -O2`). Instructions are `valgrind --tool=callgrind` totals; `grid.ms` spends 25.6M of them building the table, which the per-cell column removes.

## 2026-11-12: nested element writes

Linux x86-64, Release build with LLVM.

| build | total | per cell (4M cells) |
| --- | ---: | ---: |
| before: `dp[i][j] = v` takes the row out and puts it back | 162.7M | 34.3 |
| write through the element's address | 114.6M | 22.3 |
| plus alias regions (LLVM TBAA) | 110.6M | 21.2 |
| C (`gcc -O2`, `c/grid.c`) | 82.2M | |

- `dp[i][j] = v` lowers to `list.set` on the borrowed row `dp[i]`, written where it lies (`slot_list_set` in `ms-lower/src/native/list.rs`). The row's `ptr`, `len` and `cap` are no longer stored back after every write.
- List element accesses carry an alias region (`ms-clif/src/lower.rs`): scalar elements and list or string headers are different regions. Cranelift keeps them as alias regions; the LLVM emitter writes them as TBAA tags, so a scalar store no longer forces reloading the previous row's header.
- Remaining gap: the current row's header is still loaded each cell. Its loads sit behind a data-dependent branch, so LLVM cannot speculate them out of the loop.
- Reproduce: `ms build bench/perf/structural-gaps/grid.ms -o grid && valgrind --tool=callgrind ./grid`.
