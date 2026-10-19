# Rust and Cranelift implementation: design contract

This is the working contract for the parallel workstreams in [the proposal](../proposals/rust-cranelift-backend.md). Where the two differ, this file wins; the proposal records why. Until cutover the Go implementation stays authoritative and is the **differential-test oracle**: build it with `make build` and run `./ms`.

## Decisions (taken 2026-10-19, owner direction: keep today's behavior, maximum native speed)

1. **Behavior is preserved.** Same syntax, types, diagnostics text, CLI, JSON output and standard library as the Go implementation. The `let`/`var` keywords, reference semantics (aliasing, `.clone()` shallow copy), mutator chaining, closure snapshots and cleanup order are unchanged. Every `.ms` file in the repository must keep working without migration. A difference from Go is a bug unless this file lists it.
2. **Memory: reference counting, no tracing collector.** Heap objects carry a non-atomic reference count (the language has no concurrency). Cycles are not collected (documented leak; programs are short-lived). Speed comes from the compiler, not from changing semantics: escape analysis and scalar replacement of non-escaping records, ownership-based elision of count updates (borrow parameters, move at last use), in-place update when a count is one, inlining, range analysis and check elimination in MIR. The proposal's value-semantics model is **not** adopted (open decision card in the project thread; code written here must not depend on it either way).
3. **Faults** abort the process after running `with` cleanups in reverse order (a runtime cleanup stack, no frame unwinding in generated code). `ms test` runs each test in its own process invocation so a fault fails only that test. The 200,000-call depth limit is a per-call counter check that is elided for non-recursive call graphs.
4. **No concurrency runtime.** The language has none today. Cancellation exists only for signals/shutdown: one global flag polled in loops and calls (atomic relaxed load).
5. **Native tool: `ms profile`** replaces the debugger (the debugger and DAP are dropped). It captures sampling profiles of a native program (folded stacks, pprof-compatible output and a `perf` map file) using frame pointers plus a PC-to-source table. `perf record` works on any `ms build` output because the compiler keeps frame pointers and emits a perf map and DWARF line tables.
6. **Linking** uses the system `cc`/`ld` for now; a bundled `lld` is a follow-up (tracked as a gap).

## Pipeline and crates (`crates/`)

```text
.ms -> ms-syntax (lex, parse, AST, format)
    -> ms-check  (resolve, types, generics, contracts, effects, cleanup; typed HIR; diagnostics)
    -> ms-mir    (HIR lowering, ownership/RC elaboration, optimizer, verifier, text format, interpreter)
    -> ms-clif   (MIR -> Cranelift -> object file; line tables; perf map)
    -> linker driver + ms-rt (static runtime) -> executable
tools: ms-project (manifest, lock, aliases, import resolution), ms-tooling (lint, inspect, review, diagram, docgen, guide), ms-lsp, ms-cli (`ms`), ms-conform (conformance runner)
```

Each crate has one owner session. Cross-crate API changes go through the owner; keep public APIs small and documented with rustdoc.

## Value representation (word-level, 64-bit targets)

- `Int` i64 (checked arithmetic faults on overflow), `Float` f64, `Bool` i8 (0 or 1), `Unit` zero-sized.
- Heap objects start with a 16-byte header `{ rc: usize, drop: extern "C" fn(*mut Obj) }`; a pointer to an object points at the header. Literal and static objects use a huge `rc` so count updates are harmless and need no immortality check.
- `String` and `Bytes`: header, length, UTF-8 bytes (strings track their scalar count lazily; indices are Unicode scalar positions as in Go).
- Records: header plus fields in declaration order, each field in its natural word layout (Int/Float/Bool inline, everything else a pointer). Alternatives: header, tag, payload union sized to the largest case.
- `List[T]`: header, len, cap, data pointer; elements inline in the monomorphized layout of `T`. Runtime functions that cannot be monomorphized in Rust take an element descriptor `{ size, align, drop, eq, hash, clone }`; the compiler emits one static descriptor per element type.
- `Optional[T]`: pointer-like `T` uses the null pointer as `none`; scalars use `{ present: u8, value }`. `Result[T, E]`: tag plus payload.
- Interfaces (contract views): `{ data, vtable }` fat pointer; function values are closure objects `{ header, code, captured... }`.
- Generics are monomorphized.

The exact layouts and symbol names are documented and tested in `crates/ms-rt/ABI.md` (owned by the runtime session); the compiler reads layouts from `ms-rt-abi` constants so the two cannot drift.

## Runtime ABI rules

- `extern "C"` functions named `msrt_<module>_<name>`; native stdlib identities come from `pkg/stdlib/bindings.json` and the `.ms` declarations, which the Rust implementation embeds unchanged (they remain the signature authority).
- Fallible natives return a `Result` layout by out-pointer; faults call `msrt_fault(message_ptr, len)` which never returns.
- Reference-count rules at the boundary: arguments are borrowed unless the signature is documented as consuming; returned objects are owned (+1).

## Quality bars

- Every crate: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` green; no `unsafe` without a `// SAFETY:` comment; tests beside code.
- Parity first: diagnostics (message, position, phase, JSON shape) must match the Go implementation on the shared corpus before a Rust stage is called done.
- Performance claims need numbers from `bench/perf` on the same machine in the same run as the Go baseline.

## Workflow for sessions

- Work in your own git worktree and branch; touch only the paths you own plus `Cargo.lock`. Do not edit Go sources, documentation or skills (the integrator updates those at cutover), except the files named in your brief.
- Use `cargo` with `CARGO_TARGET_DIR` set to a directory inside your worktree. The machine has four cores shared by several sessions: prefer `cargo check` and `cargo test -p <crate>` over workspace builds, avoid `--release` unless measuring.
- Commit often with clear messages; do not push. The integrator merges branches.
- The Go oracle is `./ms` in the main checkout (`/home/user/manuscript/ms`, built). Never modify it.
