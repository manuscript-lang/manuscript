[Wiki](../index.md) › [Benchmarks and performance](index.md) › A cloned `none` that is only dropped is deleted

# A cloned `none` that is only dropped is deleted

A `var` of a large type (a `Result` holding an `Error`) that is stored to and then read keeps an optional slot. A move out of it fills the slot with `none`, and lowering takes an owned copy of that `none` and drops it at scope end. Each pass then ran the optional's clone and drop glue (about 150 instructions) on nothing. Lowering now emits an owned `opt.none_owned` (an `opt.none` is a borrow, and a `Move`-mode variable needs an owned value) instead of `clone(opt.none)`, and `simplify` deletes an owned `none` whose only uses are drops (`dropped_nones`). A loop that reassigns a `Result` variable and tests it went from 48.2M to 5.3M instructions; a layered order-processing program (interface, enum, records, Optional and Result chains) from 73.0M to 49.1M against 43.4M for the same program in C++ compiled with signed-overflow and bounds traps.

An owned `none` that is passed on stays: replacing it with the borrowed `none` fails the verifier ("moving position needs an owned value"). An immediate on `opt.none` for the owned form broke the text IR, so it is its own op. Guard: `bench/perf/guards/resultvar`.

Method for finding gaps like this: write the same program in C or C++, count instructions with `valgrind --tool=callgrind`, and read `callgrind_annotate` for glue functions that run once per pass. Compare against checked C (`-fsanitize=signed-integer-overflow,bounds -fsanitize-undefined-trap-on-error`, plus explicit length checks on heap indexing, whose bounds the sanitizer cannot see): integer and float loops, struct fields, methods and calls on records, list indexing, `match`, closures and Optional/Result checks were 0.3x to 1.1x of it; nested-list matmul 1.09x; recursive `fib` 1.95x (stack-depth check and callee-saved pushes C does not have); string `<` 1.59x (a runtime call, since inlined: see the next section).
## CSV by cell: `each_cell`

`String.view(start, end)` takes byte offsets (with a character-boundary check), so a byte-offset reader can hand out views. A function cannot return a view ("cannot return a view of `self`"), and a `List[String]` cannot hold one, so `parse` has to copy; `csv.each_cell(text, f)` instead passes each cell to `f(row, col, cell)` as a view argument. `csvgroup` on the suite input went from 1.83G to 1.15G instructions (checked C 0.53G). What is left: three runtime `index_of_byte` calls per cell (20%) and the callback body. Borrowed returns from a receiver (`proposals/borrowed-results.md`) would make `rows[i][3]` possible without copies; that is Chinmay's language decision.

## A borrowed-key insert appends once

`update`, `add` and `add_default` with a borrowed key (`m.update(k.clone(), ...)` read in place) used to copy the key to a temporary, then call `upsert_k`, which hashed and probed again before appending. The miss path now appends directly (`append_entry`): one hash, one probe, the key copied once into its slot. `dedupe` (999,874 distinct lines, the idiomatic `split(" ", 2)[0].clone()` program kept as the measured one) went from 1.75G to 1.36G instructions (checked C 0.65G); guard `mapinsert` 138.2M to 102.8M. The same program reading the first field with `line.index_of(" ")` and a `view`, which is what the C port does, is 0.84G (1.3x): the remaining gap on the idiomatic program is the list `split` builds per line, to be closed by a general fix (views or a split that does not build the list when only the first piece is used), not by rewriting the benchmark.

Profiling `@std` code: debug info names the real `src/stdlib/` source files (PR 4244), so `callgrind_annotate --auto=yes` shows per-line costs for stdlib functions with no setup.

## String `<` is generated MIR

`msrt_string_compare` is inlined (`rtstr.rs` `compare`): a byte loop over the common prefix of up to 16 bytes, read from any string form (static, inline, heap), then the lengths; longer prefixes call the runtime. String literals are static pointer strings, not inline ones, so a word-compare fast path for inline strings never fires on them. `scmp` went 77.1M to 34.8M instructions (checked C 48.4M); guard `strcmp`.

- `String` order (`compare` in `rtstr.rs`) has a path for two inline strings: they hold their bytes in the two words with zeros past the length, so two word compares and a length test decide it, with no length decode and no byte loop. On the `strings` suite program (300k sorted keys of 14 bytes) the byte-loop version cost 1.569G instructions, 6.6% above the runtime call it replaced (1.472G); the word path takes 1.445G. A static-only compare (guard-strcmp) pays about five more instructions for the failed inline test.
