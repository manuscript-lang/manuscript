# Rust and Cranelift implementation: design contract

This describes the Rust and Cranelift implementation. Current ownership rules live in [OWNERSHIP.md](ms-check/OWNERSHIP.md); exact runtime layouts and symbols live in [ABI.md](ms-rt/ABI.md) and `ms-rt-abi`.

## Decisions (taken 2026-10-19, owner direction: keep today's behavior, maximum native speed)

1. **Memory model: the proposal's value semantics, adopted by the owner on 2026-10-19.** Values have one owner and are dropped deterministically at scope end; no tracing collector and no reference counting for ordinary data. Records, lists, maps, sets, strings, bytes and alternatives are values: plain values (scalars, records of plain values) copy implicitly, others move at their last use into a consuming position, and `.clone()` duplicates explicitly (the current spelling of planned `.copy()`). `let` is immutable including contents. Mutation uses **`var`** (kept from today instead of the proposal's `mut`, to limit churn): `var` bindings and `var` parameters (marked at the declaration and at the call, `f(var xs)`) may change, and a `var` argument may not overlap another argument. Identity is explicit: `Shared[T]` (reference counted, immutable), `Weak[T]`, `Arena[T]` with generation-checked `Id[T]`. Borrows are lexical (match/if-let payloads, loop variables, `with` bindings, accessor results): the borrowed root may not be mutated or reassigned while the borrow is live; no lifetimes appear in source. Strings are immutable and may be shared by reference count (non-atomic: no concurrency). The checker implements exclusivity, projections/accessors, mutator results returning Unit, closure escape, and handle classification as described in `crates/ms-check/OWNERSHIP.md`.
2. **Ownership checking.** Ownership/exclusivity is a separate pass on checked HIR. Lowering uses its move, borrow, mutation, and drop facts; standard-library mutators use `var` receivers and return Unit.
3. **Faults** abort the process after running `with` cleanups in reverse order (a runtime cleanup stack, no frame unwinding in generated code). `ms test` runs each test in its own process invocation so a fault fails only that test. Recursive call graphs use a stack-pointer limit check at function entry; non-recursive call graphs omit it.
4. **No concurrency runtime.** The language has none today. Cancellation exists only for signals/shutdown: one global flag checked by runtime calls and I/O, not on loop back edges (atomic relaxed load).
5. **Native tool: `ms profile`** replaces the debugger (the debugger and DAP are dropped). It captures sampling profiles of a native program (folded stacks, pprof-compatible output and a `perf` map file) using frame pointers plus a PC-to-source table. `perf record` works on any `ms build` output because the compiler keeps frame pointers and emits a perf map and DWARF line tables.
6. **Linking** runs a pinned static `lld` embedded in `ms` (built by `scripts/build-llvm-bundle.sh`, cached in CI). Linux links static musl executables over the startup files and libc that `crates/ms-clif/build.rs` copies from the Rust toolchain; macOS links against `.tbd` stubs generated from the symbols the program imports. Windows links the mingw-w64 CRT and import libraries from the pinned llvm-mingw release (`scripts/fetch-mingw.sh`), with the runtime built for `gnullvm` (see `proposals/bundled-linker.md`).

## Pipeline and crates (`crates/`)

```text
.ms -> ms-syntax (lex, parse, AST, format)
    -> ms-check  (resolve, types, generics, contracts, effects, cleanup; typed HIR; diagnostics)
    -> ms-lower  (checked HIR and ownership facts to MIR, native standard calls)
    -> ms-mir    (representation, ownership elaboration, optimizer, verifier, text format, interpreter)
    -> ms-clif   (MIR -> Cranelift -> object file; line tables; perf map)
    -> linker driver + ms-native (ms-rt and the ms-std-* crates in one static library, embedded in ms) -> executable
tools: ms-project (manifest, lock, aliases, import resolution), ms-driver (module graph loading, entry rule, lowering seam, optimize, codegen and link; the `ms build/run/test/profile` engine in ms-cli sits on it), ms-tooling (lint, inspect, review, diagram), ms-guide (agent guide, `search_symbol` standard-library lookup, docgen), ms-lsp, ms-cli (`ms`), ms-conform (conformance runner)
```

Keep public crate APIs small and documented with rustdoc; cross-crate changes must preserve the shared ownership and runtime ABI contracts.

## Value representation (word-level, 64-bit targets)

- `Int` i64 (checked arithmetic faults on overflow), `Float` f64, `Bool` i8 (0 or 1), `Unit` zero-sized.
- Generated values are flattened into scalar leaves in registers and naturally aligned slots in memory; see `ms-clif/src/layout.rs`.
- `String` is a pointer to an immutable reference-counted object with a 16-byte header, byte length, scalar-count metadata, and UTF-8 data. Shared objects and closures also have reference-counted headers; ordinary owned collections do not.
- `List[T]`, `Bytes`, and `StringBuilder` use an owned three-word `{ ptr, len, cap }` value. Elements occupy the monomorphized layout of `T`; generic runtime operations receive an explicit `TypeDesc` with size, alignment, drop, equality, hashing, and copy operations.
- `Map[K, V]` and `Set[T]` use an owned six-word `MapVal` with ordered slots and a lookup index. Their owner drops elements and frees the buffers.
- Records flatten their fields in declaration order. Alternatives carry a tag and shared payload slots; recursive alternatives are boxed to make their layout finite.
- `Optional[T]` uses a nullable pointer for a single-pointer payload, otherwise a presence flag and the payload leaves. Recursive optional layouts use indirection. `Result[T, E]` uses the alternative layout.
- Interfaces use `{ data, vtable }` views; function values refer to closure objects. Non-escaping closures borrow captures; escaping closures own them, as described in the ownership rules.
- Generics are monomorphized.

## Runtime ABI rules

- Runtime symbols use `msrt_`; native standard-library symbols use `msstd_`. `stdlib/*.ms` owns public signatures and `stdlib/bindings.json` owns native identities.
- Scalars cross the C-layout ABI directly. Aggregates cross by pointer, and constructed aggregates use a trailing output pointer. Fallible calls use status codes and outputs; see [ABI conventions](ms-rt/ABI.md#1-conventions).
- Arguments are borrowed unless documented as consuming; `var` receivers are exclusive mutable pointers. Returned values are owned, while explicitly lending source operations retain the borrow relationship checked by `ms-check`.
- `ms-rt-abi` defines shared layouts and constants; its layout tests keep compiler and runtime assumptions aligned.

## Quality bars

- Every crate: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` green; no `unsafe` without a `// SAFETY:` comment; tests beside code.
- Diagnostics (message, position, phase, JSON shape) are pinned by the conformance corpus.
- Performance claims need numbers from `bench/perf` on the same machine.

## Contributor workflow

Follow [repository guidance](../AGENTS.md) and [development checks](../documentation/contributing/development.md). Documentation, declarations, and generated output have distinct owners; regenerate standard-library references with `make docs` and validate the book with `make book-check`.
