+++
title = "Function lowering"
weight = 93
+++

# Function lowering

Source has one function kind. Functions, closures, and contract methods lower to MIR functions in `ms-lower`; a closure is an object `{ header, code, captured... }` holding borrowed captures or moved owned captures according to escape analysis, and a contract view is a `{ data, vtable }` fat pointer. Generics are monomorphized, so each instantiation is an ordinary function.

- Closure creation borrows or moves captures according to ownership facts and does not run the body.
- The Rust backend does not poll for cancellation on loop back edges; one global stop flag is observed in runtime calls and I/O.
- The recursion limit is a stack-pointer comparison on entry, elided for non-recursive call graphs.

See the [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#value-representation-word-level-64-bit-targets) and the [lowering overview](_index.md).
