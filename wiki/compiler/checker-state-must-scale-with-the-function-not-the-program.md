[Wiki](../index.md) › [Compiler and build](index.md)

# Checker state must scale with the function, not the program

Verified: 2026-11-16, `ms check` on a generated 1,001-file, 123k-line project (`bench/tools/compile_time.ms`), callgrind: 11.7 B instructions before, 5.1 B after; median wall 2.05 s to 1.55 s on 4 cores. Conformance 4019 and 1460 fixtures unchanged.

- Binding uids count up across the whole checker, so an array indexed by uid costs the program's binding count per function. The ownership walker's borrow arrays zeroed hundreds of kilobytes per function (`memset` was 8% of the run). `ByBinding` in `ownership/walk/active.rs` stores only the span of uids a function touches.
- A loop over `Program::methods` per type question is quadratic. Structural property lookup (`Equal`, `Hashable`) reads `PropertyMethods`, positions in method order that `add_method` extends as it pushes; a future in-place edit of a method's contract or name would make it stale, so keep additions in `add_method`.
- Do not clone `Info` to read one field: read `facts().info(id)` in place (`Checker::with_info`). The effect scan cloned it up to five times per expression.
- A pass that copies every declaration to rewrite a few of them should borrow when it has nothing to rewrite (`expand_set_receivers` returns `Cow`).
- `closeable` is asked at every binding; its answer depends only on the current file, the method count and the type shape, so a type without variables is memoized under that key. A variable's bounds are filled in after creation and are not in the shape, so types with variables are never cached.
- `holds_resource` scanned every method of the program per type probed; it now walks `PropertyMethods::closing`, the methods that close their receiver (1.20 B to 1.09 B instructions on a 150-file project).
- Reading a name (`Names::str`) is lock-free: texts live in append-only segments, and only `intern` takes the mutex. The old mutex per read was 6% of a check.

Apply when: adding per-function state or a scan in `ms-check`. Profile with `valgrind --tool=callgrind ms check` in a generated project, not a small one: these costs only show with a large uid space and many methods.
