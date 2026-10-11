+++
title = "With scopes"
weight = 54
+++

# With scopes

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

`with` initializes an immutable binding and registers the cleanup operation for exit from the indented body. A concrete type must explicitly implement `Closeable`; a contract type must explicitly declare `fn close() -> Unit`; a generic parameter must have a bound proving either operation, as specified by [Closeable](closeable.md).

```text
with file = try files.open(path: "data.txt"):
    let chunk = try file.read(max_bytes: 4096)
```

This is a body fragment in a function returning `Result[U, IoError]`, with an explicit files capability. A read returns `Optional[Bytes]`: match the chunk to distinguish data from EOF. The standard Files.open result retains a shared File view.

The initializer evaluates once. If it fails, no close action is registered. After successful acquisition, registration occurs before any further cancellation checkpoint. Fallthrough, `break`, `continue`, return, propagated error, programming fault, and cancellation execute the registered action for each scope exited, from inner to outer.

Resources acquired through `with` in a loop close at the end of that iteration. An ordinary resource-valued `let` declaration does not implicitly register cleanup. Returning or capturing a registered object does not remove the action.

`with` is the language construct; file, transaction, and `Background` behavior comes from ordinary contract implementations. There is no user-defined enter hook or error-suppression hook in this contract.

Go's function-level `defer` does not have Manuscript's block lifetime. The compiler explicitly lowers cleanup scopes and unwind paths. [Go defer specification](https://go.dev/ref/spec#Defer_statements)

See [Closeable](closeable.md), [exit ordering](exit-order.md), and [lowering](../../compiler/lowering/cleanup-and-faults.md).
