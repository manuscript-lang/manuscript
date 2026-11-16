[Wiki](../index.md) › [Benchmarks and performance](index.md) › A cloned `none` that is only dropped is deleted

# A cloned `none` that is only dropped is deleted

A `var` of a large type (a `Result` holding an `Error`) that is stored to and then read keeps an optional slot. A move out of it fills the slot with `none`, and lowering takes an owned copy of that `none` and drops it at scope end. Each pass then ran the optional's clone and drop glue (about 150 instructions) on nothing. `simplify` now deletes a clone of `opt.none` whose only uses are drops, with those drops (`dead_none_clones`). A loop that reassigns a `Result` variable and tests it went from 48.2M to 5.3M instructions; a layered order-processing program (interface, enum, records, Optional and Result chains) from 73.0M to 49.1M against 43.4M for the same program in C++ compiled with signed-overflow and bounds traps.

A clone that is passed on stays: replacing it with the borrowed `none` fails the verifier ("moving position needs an owned value"). Guard: `bench/perf/guards/resultvar`.

Method for finding gaps like this: write the same program in C or C++, count instructions with `valgrind --tool=callgrind`, and read `callgrind_annotate` for glue functions that run once per pass. Compare against checked C (`-fsanitize=signed-integer-overflow,bounds -fsanitize-undefined-trap-on-error`, plus explicit length checks on heap indexing, whose bounds the sanitizer cannot see): integer and float loops, struct fields, methods and calls on records, list indexing, `match`, closures and Optional/Result checks were 0.3x to 1.1x of it; nested-list matmul 1.09x; recursive `fib` 1.95x (stack-depth check and callee-saved pushes C does not have); string `<` 1.59x (a runtime call).
