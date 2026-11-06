[Wiki](../index.md) › [Compiler and build](index.md)

# `ms-check` exposes only its `api` module

Verified: 2026-11-06, Track E of `proposals/rust-simplification.md`.

Apply when: a sibling crate needs a checker type or query, or you add a `pub` item to `ms-check`.

- `crates/ms-check/src/api.rs` is the only public surface. Every other module is private, so rustc reports unused items inside them instead of treating them as exported.
- Add a `pub use` line to `api.rs` to widen the contract; that line is the review point. Do not make a module `pub` again.
- Tests that need checker internals (type constructors, `type_key`) live inside the crate as `*_tests.rs`, not in `tests/`.
- `ms-repo-check` (`layering.rs`) lists the allowed normal dependencies of each compiler crate. Compiler crates reach the runtime only through `ms-rt-abi`; a runtime-only test edge goes in `[dev-dependencies]`.
- `ms-decimal` is the pure Decimal arithmetic (no runtime dependency); `ms-lower` folds literals with it and `ms-std-decimal` only wraps it in the C ABI. Keep new compiler-side helpers out of `ms-std-*` crates for the same reason.
- `ms_check::api` also re-exports the syntax vocabulary lowering walks (`ast`, `visit`, `number`, `Names`, `NodeId`, `Pos`), so `ms-lower` has no `ms-syntax` dependency of its own.
- `editor.rs` (member and import-completion queries) is a leaf over the checker: no checker module names `crate::editor` (repo-check enforces it). It stays in the crate because it needs `Checker` and method resolution internals; a separate crate would have to export those. `hints.rs` and `suggestions.rs` are checker diagnostics, not editor code.
