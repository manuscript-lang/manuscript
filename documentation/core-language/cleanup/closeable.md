+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

`Closeable` is the standard cleanup contract. Import it from `@std/cleanup.ms` to name or implement it. A `with` block checks the identity of that standard contract, so an unrelated interface with the same spelling does not replace it. Its declaration is:

```manuscript
interface Closeable:
    fn close() -> Unit
```

For a concrete value the compiler requires its explicit `Closeable` implementation, resolves that method, and registers a call to it. A contract value is also eligible when its own declaration explicitly contains the exact operation `fn close() -> Unit`; register that declared operation without a contract-to-contract conversion. A similarly named concrete method without `impl Closeable` remains insufficient. This rule lets standard `File`, `ReadStream`, and `WriteStream` contracts expose cleanup and admit source test fakes without inheritance. It has no special knowledge of a particular file or transaction. Libraries can implement the same cleanup contract for their own managed objects.

A generic parameter with a Closeable bound also supplies the implementation proof needed by with; dispatch its bound close operation directly without constructing a view or adding a sharing bound. A generic bound naming a contract that explicitly declares the exact close signature is likewise sufficient. An unconstrained type parameter or a merely similarly named method is insufficient.

`close()` is idempotent, may suspend like any other function, and finishes the object's release/shutdown obligation before returning. Repeated or concurrent calls do not release an underlying handle twice. An implementation must coordinate ongoing access with closure and ensure that later accesses report closed state.

Expected failures that application code needs to handle belong to explicit operations such as `commit()`, `flush()`, or `finish()`, returning `Result`. The automatic close hook returns `Unit`; an unexpected release failure is a programming/cleanup fault, not a discarded error value.

A close failure does not skip other registered actions. Implementations must leave the object unusable or safely quarantined after a failed release rather than exposing an invalid/reused native handle. Faults and remaining release obligations are reported to the host.

General user `defer` syntax is unsupported. Custom scope cleanup can be packaged in a library object implementing `Closeable`.

See [using with](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
