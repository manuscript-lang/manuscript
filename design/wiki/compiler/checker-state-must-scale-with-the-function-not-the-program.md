[Wiki](../index.md) › [Compiler and build](index.md)

# Checker state must scale with the function, not the program

Verified (Rust `ms`, kept as the pattern): 2026-11-16, `ms check` on a generated 1,001-file, 123k-line project (`bench/perf/tools/compile_time.ms`), callgrind: 11.7 B instructions before, 5.1 B after; median wall 2.05 s to 1.55 s on 4 cores. Conformance 4019 and 1460 fixtures unchanged.

- Binding ids count up across the whole checker, so an array indexed by binding costs the program's binding count per function. Per-function state (borrow arrays, live sets) must cover only the span of ids a function touches; the Rust walker's zeroed arrays were 8% of the run (`memset`).
- A loop over every method of the program per type question is quadratic: keep per-property method lists (structural `Equal`/`Hashable` lookup, types that close their receiver) and extend them where methods are added (`compiler/check/properties.c`).
- Do not copy a fact record to read one field; read it in place. A pass that copies every declaration to rewrite a few should borrow when it has nothing to rewrite.
- A per-binding question (whether a type is closeable) is memoized only when its answer depends on the type's shape alone; a type variable's bounds are filled in after creation and are not in the shape, so types with variables are never cached.
- Reading a name is lock-free in the Rust interner; the C `MsNames` table is per-thread data and takes no lock (`src/base/intern.h`).

Apply when: adding per-function state or a scan in `compiler/check` or `compiler/own`. Profile with `valgrind --tool=callgrind ms check` in a generated project, not a small one: these costs only show with a large uid space and many methods.
