# Rust and Cranelift implementation: design contract

This is the working contract for the parallel workstreams in [the proposal](../proposals/rust-cranelift-backend.md). Where the two differ, this file wins; the proposal records why.

## Decisions (taken 2026-10-19, owner direction: keep today's behavior, maximum native speed)

1. **Memory model: the proposal's value semantics, adopted by the owner on 2026-10-19.** Values have one owner and are dropped deterministically at scope end; no tracing collector and no reference counting for ordinary data. Records, lists, maps, sets, strings, bytes and alternatives are values: plain values (scalars, records of plain values) copy implicitly, others move at their last use into a consuming position, and `.copy()` duplicates explicitly. `let` is immutable including contents. Mutation uses **`var`** (kept from today instead of the proposal's `mut`, to limit churn): `var` bindings and `var` parameters (marked at the declaration and at the call, `f(var xs)`) may change, and a `var` argument may not overlap another argument. Identity is explicit: `Shared[T]` (reference counted, immutable), `Weak[T]`, `Arena[T]` with generation-checked `Id[T]`. Borrows are lexical (match/if-let payloads, loop variables, `with` bindings, accessor results): the borrowed root may not be mutated or reassigned while the borrow is live; no lifetimes appear in source. Strings are immutable and may be shared by reference count (non-atomic: no concurrency). Open design items (exclusivity corpus, projections/accessors, mutator results returning Unit, closure escape as a signature property, generic copyability bound, handle types) are settled in `crates/ms-check/OWNERSHIP.md` by the checker session and the stdlib delta by a later session; everything else in this file is independent of them.
2. **Staging.** Ownership/exclusivity is a separate pass and standard-library signature changes (mutator results, accessors) land as one reviewed delta with an `ms migrate` tool that rewrites the repository's `.ms` files.
3. **Faults** abort the process after running `with` cleanups in reverse order (a runtime cleanup stack, no frame unwinding in generated code). `ms test` runs each test in its own process invocation so a fault fails only that test. The 200,000-call depth limit is a per-call counter check that is elided for non-recursive call graphs.
4. **No concurrency runtime.** The language has none today. Cancellation exists only for signals/shutdown: one global flag checked by runtime calls and I/O, not on loop back edges (atomic relaxed load).
5. **Native tool: `ms profile`** replaces the debugger (the debugger and DAP are dropped). It captures sampling profiles of a native program (folded stacks, pprof-compatible output and a `perf` map file) using frame pointers plus a PC-to-source table. `perf record` works on any `ms build` output because the compiler keeps frame pointers and emits a perf map and DWARF line tables.
6. **Linking** runs a pinned static `lld` embedded in `ms` (built by `scripts/build-llvm-bundle.sh`, cached in CI). Linux links static musl executables over the startup files and libc that `crates/ms-clif/build.rs` copies from the Rust toolchain; macOS links against `.tbd` stubs generated from the symbols the program imports. Windows still uses the system `clang` until its bundled path lands (see `proposals/bundled-linker.md`).

## Pipeline and crates (`crates/`)

```text
.ms -> ms-syntax (lex, parse, AST, format)
    -> ms-check  (resolve, types, generics, contracts, effects, cleanup; typed HIR; diagnostics)
    -> ms-mir    (HIR lowering, ownership/RC elaboration, optimizer, verifier, text format, interpreter)
    -> ms-clif   (MIR -> Cranelift -> object file; line tables; perf map)
    -> linker driver + ms-native (ms-rt and the ms-std-* crates in one static library, embedded in ms) -> executable
tools: ms-project (manifest, lock, aliases, import resolution), ms-driver (module graph loading, entry rule, lowering seam, optimize, codegen and link; the `ms build/run/test/profile` engine in ms-cli sits on it), ms-tooling (lint, inspect, review, diagram), ms-guide (agent guide, `search_symbol` standard-library lookup, docgen), ms-lsp, ms-cli (`ms`), ms-conform (conformance runner)
```

Each crate has one owner session. Cross-crate API changes go through the owner; keep public APIs small and documented with rustdoc.

## Value representation (word-level, 64-bit targets)

- `Int` i64 (checked arithmetic faults on overflow), `Float` f64, `Bool` i8 (0 or 1), `Unit` zero-sized.
- Heap objects start with a 16-byte header `{ rc: usize, drop: extern "C" fn(*mut Obj) }`; a pointer to an object points at the header. Literal and static objects use a huge `rc` so count updates are harmless and need no immortality check.
- `String` and `Bytes`: header, length, UTF-8 bytes (strings track their scalar count lazily; indices are Unicode scalar positions).
- Records: header plus fields in declaration order, each field in its natural word layout (Int/Float/Bool inline, everything else a pointer). Alternatives: header, tag, payload union sized to the largest case.
- `List[T]`: header, len, cap, data pointer; elements inline in the monomorphized layout of `T`. Runtime functions that cannot be monomorphized in Rust take an element descriptor `{ size, align, drop, eq, hash, clone }`; the compiler emits one static descriptor per element type.
- `Optional[T]`: pointer-like `T` uses the null pointer as `none`; scalars use `{ present: u8, value }`. `Result[T, E]`: tag plus payload.
- Interfaces (contract views): `{ data, vtable }` fat pointer; function values are closure objects `{ header, code, captured... }`.
- Generics are monomorphized.

The exact layouts and symbol names are documented and tested in `crates/ms-rt/ABI.md` (owned by the runtime session); the compiler reads layouts from `ms-rt-abi` constants so the two cannot drift.

## Runtime ABI rules

- `extern "C"` functions named `msrt_<module>_<name>`; native stdlib identities come from `stdlib/bindings.json` and the `.ms` declarations, which the Rust implementation embeds unchanged (they remain the signature authority).
- Fallible natives return a `Result` layout by out-pointer; faults call `msrt_fault(message_ptr, len)` which never returns.
- Reference-count rules at the boundary: arguments are borrowed unless the signature is documented as consuming; returned objects are owned (+1).

## Quality bars

- Every crate: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` green; no `unsafe` without a `// SAFETY:` comment; tests beside code.
- Diagnostics (message, position, phase, JSON shape) are pinned by the conformance corpus.
- Performance claims need numbers from `bench/perf` on the same machine.

## Workflow for sessions

- Work in your own git worktree and branch; touch only the paths you own plus `Cargo.lock`. 
- Use `cargo` with `CARGO_TARGET_DIR` set to a directory inside your worktree. The machine has four cores shared by several sessions: prefer `cargo check` and `cargo test -p <crate>` over workspace builds, avoid `--release` unless measuring.
- Commit often with clear messages; do not push. The integrator merges branches.
