+++
title = "Lowering"
weight = 2
+++

# Lowering

Lowering translates checked Manuscript into MIR, which `ms-mir` optimizes and verifies and `ms-clif` turns into native code through Cranelift. It preserves evaluation order, closure captures, and block-level cleanup.

## Typed values

Every Manuscript type has one word-level representation: `Int` is `i64`, `Float` is `f64`, `Bool` is `i8`, records and alternatives are heap objects with a 16-byte header, and `List[T]` stores elements inline in the layout of `T`. There is no universal value type or boxing; generics are monomorphized. The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#value-representation-word-level-64-bit-targets) states the layouts, and the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) state when a value moves, borrows, or copies.

- `ms-lower` consumes the checked HIR and ownership facts and builds MIR; native standard calls use the `msrt_` and `msstd_` symbols in `crates/ms-rt/ABI.md`.
- `ms-mir` verifies every module it produces and has a text format and interpreter for tests.
- `ms-clif` is the only stage that knows the target machine.

## Source locations and fault frames

- Generated code keeps frame pointers and DWARF line tables, so a fault reports source frames without per-call bookkeeping.
- The call depth limit is a per-call counter check that is elided for non-recursive call graphs.

## Defaults belong to the callee

- Source functions bind a defaulted parameter in the callee prologue, so defaults can read earlier parameters and `try` returns from the callee.
- Native functions, record constructors, and runtime contracts take plain parameters; call sites evaluate their defaults.

## Equality and keys

Types whose machine equality is Manuscript equality (scalars, strings, `Duration`, `Timestamp`, handles, `Unit`) compare directly. Runtime collections of other element types take an element descriptor with `eq`, `hash`, and `clone` entries emitted by the compiler.

## Implementation scope

Implementations are visible only in their declaring module. A generic instantiated from another module resolves its type variables' contract operations against the instantiating module first, then its own.

- [Function lowering](function-calls.md)
- [Source guarantees and representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
