+++
title = "Lowering"
weight = 2
+++

# Lowering

Lowering translates checked Manuscript into MIR, which `compiler/mir` and `compiler/opt` optimize and verify and `compiler/emit` turns into LLVM IR that the pinned LLVM tools compile to native code. It preserves evaluation order, closure captures, and block-level cleanup.

## Typed values

Every Manuscript type has one word-level representation: `Int` is `i64`, `Float` is `f64`, `Bool` is `i8`, ordinary records flatten their fields, `Error` uses a pointer to its fields, and alternatives use a tag and payload (boxed when recursive), and `List[T]` is an owned `{ ptr, len, cap }` value with inline elements. There is no universal boxed value type; generics are monomorphized. The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#value-representation-word-level-64-bit-targets) states the layouts, and the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) state when a value moves, borrows, or copies.

- `compiler/lower` consumes the checked HIR and ownership facts and builds MIR; native standard calls use the `msrt_` and `msstd_` symbols in `src/abi/README.md`.
- `compiler/mir` verifies every module it produces and has a text format.
- `compiler/emit` and `compiler/link` are the only stages that know the target machine.

## Source locations and fault frames

- Generated code keeps frame pointers and DWARF line tables, so a fault reports source frames without per-call bookkeeping.
- Recursive functions compare the stack pointer with the current task segment limit on entry. Crossing it transfers the call through a grow shim to a new segment; exhausting the task stack budget faults. Non-recursive call graphs omit this entry check.

## Defaults belong to the callee

- Source functions bind a defaulted parameter in the callee prologue, so defaults can read earlier parameters and `?` returns from the callee.
- Native functions, record constructors, and runtime contracts take plain parameters; call sites evaluate their defaults.

## Equality and keys

Types whose machine equality is Manuscript equality (scalars, strings, `Duration`, `Timestamp`, handles, `Void`) compare directly. Runtime collections of other element types take an element descriptor with `eq`, `hash`, and `copy` entries emitted by the compiler.

## Implementation scope

Implementations in a type's defining module are available wherever that type is used; extensions for imported types stay local to their declaring module. A generic instantiated from another module resolves its type variables' contract operations against the instantiating module first, then its own.

- [Function lowering](function-calls.md)
- [Source guarantees and representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
