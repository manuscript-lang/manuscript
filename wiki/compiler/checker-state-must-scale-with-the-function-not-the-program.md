[Wiki](../index.md) › [Compiler and build](index.md)

# Checker state must scale with the function, not the program

Verified: 2026-11-16, `ms check` on a generated 1,001-file, 123k-line project (`bench/tools/compile_time.ms`), callgrind: 11.7 B instructions before, 5.1 B after; median wall 2.05 s to 1.55 s on 4 cores. Conformance 4019 and 1460 fixtures unchanged.

- Binding uids count up across the whole checker, so an array indexed by uid costs the program's binding count per function. The ownership walker's borrow arrays zeroed hundreds of kilobytes per function (`memset` was 8% of the run). `ByBinding` in `ownership/walk/active.rs` stores only the span of uids a function touches.
- A loop over `Program::methods` per type question is quadratic. Structural property lookup (`Equal`, `Hashable`, `Comparable`) reads `PropertyMethods`, positions kept in method order and extended as methods are added; a method never changes contract or name after it is pushed.
- Do not clone `Info` to read one field: read `facts().info(id)` in place (`Checker::with_info`). The effect scan cloned it up to five times per expression.
- A pass that copies every declaration to rewrite a few of them should borrow when it has nothing to rewrite (`expand_set_receivers` returns `Cow`).
- `closeable` is asked at every binding; its answer depends only on the current file, the method count and the type shape, so it is memoized under that key.

Apply when: adding per-function state or a scan in `ms-check`. Profile with `valgrind --tool=callgrind ms check` in a generated project, not a small one: these costs only show with a large uid space and many methods.
