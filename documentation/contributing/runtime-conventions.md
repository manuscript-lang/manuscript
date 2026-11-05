+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

`ms-rt` is the native runtime that generated code links against, and each `ms-std-*` crate implements one standard module. Each standard native operation is one C-ABI function with a signature the compiler calls directly, so no value is boxed or type-erased at the boundary.

## The contract comes from declarations

`stdlib/*.ms` holds the `@std` declarations, with `extern type` for opaque types and `extern fn` for native symbols. They are the signature authority and the Rust implementation embeds them unchanged. `ms-lower` reads them to emit native calls; the layouts and symbol catalogue are in `crates/ms-rt/ABI.md`, and the compiler reads layout constants from `ms-rt-abi` so the two cannot drift. A wrong-looking signature is a declaration or lowering issue, not something to patch in the runtime.

## Naming and shape

- Runtime functions are `extern "C"` and named `msrt_<module>_<name>`; standard-library natives live in `ms-std-<module>` crates and are named `msstd_<module>_<name>`.
- Fallible natives return a status and write their result to an out-pointer only on success; faults call `msrt_fault`, which never returns. Use a fault only for documented programming faults.
- Ownership at the boundary: arguments are borrowed unless the signature is documented as consuming; returned objects are owned.
- Native functions, record constructors, and contracts take plain parameters; callers evaluate defaults.
- Long-running operations check the cancellation flag; blocking calls wait in short slices so a pending stop request interrupts them.
- Generics are monomorphized. Shared collection routines take a `TypeDesc` describing slot size, alignment, kind, child descriptors, and optional `drop`, `copy`, `eq` and `hash` operations. Read its exact layout in `ms-rt-abi`; do not duplicate offsets in native code.

## Representation

Values have one owner and are dropped deterministically; records, lists, maps, sets, strings, and alternatives are values, not aliased references. The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the word-level layouts, and the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) state moves, borrows, and `var` parameters.

## Host escalation

Cleanup waits for work to end. The runtime cannot terminate work that ignores cancellation, so such work can block cleanup forever. Escalation is the host's last resort: it ends the process and never reports stuck work as joined.

The native process starts a grace timer after its first stop signal (SIGINT or SIGTERM), while cancellation and stop hooks ask running work to finish. Ordinary promise deadlines do not arm this process timer. The timer includes any scope-end cleanup and resource close that follows the stop request.

| Setting | Default |
| --- | --- |
| Grace period after the stop request | 30 seconds |
| A second stop request during the grace period | Escalates immediately |

On escalation, `crates/ms-rt/src/start.rs` writes an `incomplete cleanup: <reason>` diagnostic to stderr and an incomplete-cleanup fault record, then exits 67 without further cleanup. It does not report each outstanding operation separately. The grace period is fixed. Test both the grace-expiry and second-request paths when changing shutdown handling; see [cleanup faults](../core-language/cleanup/cleanup-faults.md).

## Verifying

- `cargo clippy -p ms-rt -p ms-rt-abi --all-targets -- -D warnings` and `cargo nextest run -p ms-rt`.
- `make unit` runs every crate's tests, and `make conform` runs programs end to end.
