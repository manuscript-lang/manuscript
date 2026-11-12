# Constant list tables iterated in a loop are built once

Grid searches write their direction table inside the loop: `for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:`. Lowering built the nested literal (five allocations) and dropped it on every pass: 50 ns per pass, 248 ms for 5M passes against 2 ms for Rust, which folds the array away.

- `ms-lower/src/hoist.rs`: the outermost loop (`for_stmt` and `while_stmt`) scans its body, outside closures, for `for` statements whose iterable is a non-empty literal of at most 32 constant scalars, or of such lists. Each is built once into a hidden local of the loop's scope (dropped with it on every exit) and the inner `for` borrows it by node id. The map is cleared when the outermost loop ends.
- The inner loop uses the hoisted list only when its variable is borrowed (not moved on, not slotted), the same test the normal path uses to avoid copying; otherwise it builds its own.
- Result: 248 ms to about 20 ms on the 5M-pass microbenchmark; `c16-maze-bfs` gains under 10%, inside the VM's noise.
- Not done: tables bound with `:=` outside the loop already work; a literal used as an argument or in a condition inside a loop is still built per pass (extend `hoist_literals` with a second pattern and a test if one shows up).
- Evidence: fixture `e2e/accept/loop-constant-literal-tables`; `bench/perf/codegen-2026-11-12.md`.
