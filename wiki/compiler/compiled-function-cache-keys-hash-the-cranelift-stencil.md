[Wiki](../index.md) › [Compiler and build](index.md)

# Compiled-function cache keys hash the Cranelift stencil

Verified: 2026-11-16, 1,001-file generated project, Debug, 4 cores. With every function cached, `ms build` takes 4.7 s against 5.9 s cold: the 2.4 s front end, MIR and linking are not cached, and the key (0.3 s) plus lowering to Cranelift IR (0.6 s) still run for every function.

- The key is a hash of `Function::stencil` (what Cranelift's own incremental cache hashes) with the source-location table taken out, plus the symbol name behind each user reference, the resolved `(file, line, scope relative to the function)` of every instruction, the `Func` name and position, the named values and the target, flags and `ms` executable stamp. Hashing formatted CLIF text cost 1.1 s; the stencil hash costs 0.3 s.
- Symbol and data names in the IR are content-derived, so an unrelated edit does not change another function's key. An edit that moves a function's line numbers does: adding a statement recompiled 11 functions, the rest of its file.
- A hit still lowers the function: strings, data, glue and location tables are made as usual, and only `define_function` is skipped.
- One file per target holds the newest generation (this build's entries first, older ones while under 128 MiB), so the cache stays bounded and a build with only hits writes nothing.
- A release build with LLVM uses none of this for functions: LLVM units shift when anything is added (names carry indexes, cuts follow cumulative size), see `proposals/incremental-builds.md`.

Apply when: changing the Cranelift lowering, symbol naming or source-location interning.
Evidence: `crates/ms-clif/src/codecache.rs`, `function_key` in `cg.rs`, `crates/ms-cli/tests/code_cache.rs`.
Verify: `MS_TIMINGS=1 ms build` prints `code cache N hits, M compiled`; a rebuild after a one-function edit compiles about one function and the executable equals an `MS_CACHE=off` build.
