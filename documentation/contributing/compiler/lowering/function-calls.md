+++
title = "Function lowering"
weight = 93
+++

# Function lowering

Source has one function kind. Functions, closures, and contract methods lower to MIR functions in `ms-lower`; a closure is an object `{ header, code, captured... }` holding borrowed captures or moved owned captures according to escape analysis, and a contract view is a `{ data, vtable }` fat pointer. Generics are monomorphized, so each instantiation is an ordinary function.

- Closure creation borrows or moves captures according to ownership facts and does not run the body.
- The Rust backend does not poll for cancellation on loop back edges; cancellation is delivered through the current task at waits.
- Recursive calls use the [segmented-stack entry check](_index.md#source-locations-and-fault-frames). A grow shim preserves parameters and results when a call needs another segment.

See the [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#value-representation-word-level-64-bit-targets) and the [lowering overview](_index.md).
