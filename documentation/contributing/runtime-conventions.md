+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

The C runtime under `src/runtime/` is what generated code links against, and each module under `src/runtime/std/` implements one standard module. Each standard native operation is one C-ABI function with a signature the compiler calls directly, so no value is boxed or type-erased at the boundary.

## The contract comes from declarations

`src/stdlib/*.ms` holds the `@std` declarations, with `extern type` for opaque types and `extern fn` for native symbols. They are the signature authority. `compiler/lower` reads them to emit native calls; the layouts and symbol catalogue are in `src/abi/README.md`, and the compiler reads layout constants from `src/abi` so the two cannot drift. A wrong-looking signature is a declaration or lowering issue, not something to patch in the runtime.

## Naming and shape

- Runtime functions are C functions named `msrt_<module>_<name>`; standard-library natives live in `src/runtime/std/` and are named `msstd_<module>_<name>`.
- Fallible natives return a status and write their result to an out-pointer only on success; faults call `msrt_fault`, which never returns. Use a fault only for documented programming faults.
- Ownership at the boundary: arguments are borrowed unless the signature is documented as consuming; returned objects are owned.
- Native functions, record constructors, and contracts take plain parameters; callers evaluate defaults.
- Long-running operations check the cancellation flag; blocking calls wait in short slices so a pending stop request interrupts them.
- Generics are monomorphized. Shared collection routines take a `TypeDesc` describing slot size, alignment, kind, child descriptors, and optional `drop`, `copy`, `eq` and `hash` operations. Read its exact layout in `src/abi`; do not duplicate offsets in native code.

## Representation

Values have one owner and are dropped deterministically; records, lists, maps, sets, strings, and alternatives are values, not aliased references. The [ABI notes](https://github.com/manuscript-lang/manuscript/blob/main/src/abi/README.md) record the word-level layouts, and the [ownership rules](ownership-rules.md) state moves, borrows, and `var` parameters.

## Host escalation

Cleanup waits for work to end. The runtime cannot terminate work that ignores cancellation, so such work can block cleanup forever. Escalation is the host's last resort: it ends the process and never reports stuck work as joined.

The native process starts a grace timer after its first stop signal (SIGINT or SIGTERM), while cancellation and stop hooks ask running work to finish. Ordinary promise deadlines do not arm this process timer. The timer includes any scope-end cleanup and resource close that follows the stop request.

| Setting | Default |
| --- | --- |
| Grace period after the stop request | 30 seconds |
| A second stop request during the grace period | Escalates immediately |

On escalation, the runtime entry (`src/runtime/entry/`) writes an `incomplete cleanup: <reason>` diagnostic to stderr and an incomplete-cleanup fault record, then exits with the fault status (134) without further cleanup. It does not report each outstanding operation separately.

The grace period is fixed. Test both the grace-expiry and second-request paths when changing shutdown handling; see [cleanup faults](../core-language/cleanup/cleanup-faults.md).

## Verifying

- `ctest --preset ci` and `cmake --build --preset ci --target lint`.
- `make unit` runs every crate's tests, and `make conform` runs programs end to end.
