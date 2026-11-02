[Wiki](../index.md) › [Compiler and build](index.md)

# Compiler change checklist

Verified: rules gathered from past compiler, syntax, and build work; the linked lessons carry the evidence.

Apply when: changing `ms-syntax`, `ms-check`, `ms-mir`, `ms-lower`, `ms-clif`, `ms-driver`, `ms-build`, or `ms-native`.

Use for `crates/ms-syntax`, `ms-check`, `ms-mir`, `ms-lower`, `ms-clif`, `ms-driver`, `ms-build`, or `ms-native`. Read [architecture](../../documentation/contributing/architecture.md), [Rust toolchain](../../documentation/contributing/rust-toolchain.md), `crates/DESIGN.md`, relevant [compiler rules](../../documentation/contributing/compiler/_index.md), and [language](../language/index.md) / [compiler lessons](index.md); syntax work also reads the [grammar](../../documentation/core-language/basics/grammar.md) and [editor recovery lessons](../tooling-and-docs/editor-recovery-must-preserve-delimiter-continuations.md).

- Pipeline: `ms-syntax` (lexer, parser, formatter) -> `ms-check` (resolution, types, contracts, effects, cleanup, ownership; typed HIR) -> `ms-lower` and `ms-mir` (MIR, ownership elaboration, optimizer, verifier) -> `ms-clif` (Cranelift object code) -> `ms-driver` (module graph, entry rule) and `ms-build` (lowering seam, codegen, link). Keep parse/resolution/type/lowering diagnostics attributable to source.
- Preserve source-only analysis: recovery is editor analysis, and diagnostics prevent executable generation. Entry validation independently checks `export fn main() Int`.
- Resolve nominal symbols, implementations, defaults, and effects in checking; reuse checked identities in consumers. Do not infer semantics from spelling.
- Retain module-local implementation selection through views, bound methods, generics, and cleanup. Defaults must not survive mutable callable replacement or generic inference as omission permissions.
- An implementation names its parameters like the interface: lowering labels arguments of a call through the interface by the interface's names, so a renamed parameter (`fn equals(o: P)`) once passed check and failed lowering with "no parameter other". The checker now rejects it (`impl_parameter_names` test).
- Keep manifest/alias/path/overlay identity in `ms-driver`'s `project` module. Resolver changes need symlinked roots, confined unsaved files, dangling links, conflicting overlays, and malformed nested manifest cases.
- Lower in source evaluation order, including defaults and cleanup on every exit. The [lowering pages](../../documentation/contributing/compiler/lowering/_index.md) and `crates/DESIGN.md` record value layout and the runtime ABI; use the [runtime checklist](../runtime/runtime-and-stdlib-change-checklist.md) for execution contracts. Write the AGENTS.md proposal with an independent skeptical review before changing fault-frame, cancellation, dispatch, or representation semantics.
- Ownership and `var` rules live in `crates/ms-check/OWNERSHIP.md`. Do not add code only to reproduce old Go output where Rust std covers the concept.
- A long list literal of scalar constants lowers to `list.const` (static data memcpy'd into a fresh list), never to one function as long as the literal: register allocation, SLP and the scheduler are quadratic in function length. A long literal of runtime values is built in 64-element `list.lit` chunks joined by `list.concat`, each chunk outlined into a helper function (`FuncBuilder::outline`) so no function grows with the literal and no pass is disabled. A chunk that reads a value needing a drop stays in place.
- Choose the right algorithm and data structure: passes stay linear (or n log n) in source size. Share visited sets/memos across roots, index instead of rescanning, and avoid per-byte or per-query allocation. Time `ms check` and `ms build` at N/2N/4N and profile anything above 2x per doubling; see [the lesson](compiler-passes-use-the-right-algorithm-and-data-structure-f.md).
- Run `cargo nextest run --workspace`, `make repo-check`, and `make conform` (the frozen conformance corpus in `tests/conformance/`; known differences are in `expect-fail.txt`). Execute changed semantics through corpus programs; build/link changes need a native artifact and `make dist-check`. Declaration-only acceptance does not establish execution.

## Syntax and parsing

- `crates/ms-syntax/src/ast.rs` owns the untyped tree and positions; checked semantics belong in `ms-check`. Keep syntax independent of checker/runtime/editor machinery.
- Update parser, checker, lowering, formatting, and inspection consumers together when a syntax node changes. `make repo-check` checks nested matches, `.ms` formatting, and stdlib syntax.
- Use the shared visitor in `crates/ms-syntax/src/visit.rs` for executable traversal: defaults, interpolation, collections, closures, branches, and match bodies in source order. Do not manufacture statements to visit defaults. Types/patterns need separate handling.
- Preserve file identity and original offset/line/column positions. Check LF/CRLF and editor position conversion when slicing/recovery changes; synthetic repairs must not shift valid declarations.
- Exercise strict parsing and editor partial parsing (`partial.rs`). Incomplete neighboring declarations must not erase multiline parameters or scopes. Use lexer continuation boundaries instead of splitting at lines/closing delimiters.
- Inline suites stop at enclosing delimiters, implicitly return expressions only in callable bodies, and enforce one statement/conditional branch per line. Follow current grammar rather than restoring blanket indentation restrictions.
- Route new shapes through [tooling](../tooling-and-docs/tooling-change-checklist.md). Verify traversal, accepted/rejected parsing, recovery, formatting idempotence, and affected editor scopes/navigation. Preserve reproducible parser failures as regression tests.
