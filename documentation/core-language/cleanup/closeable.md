+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Import `Closeable` from `@std/cleanup.ms` to name or implement it. `with` checks the identity of this standard contract; an unrelated same-named interface does not qualify.

```manuscript
interface Closeable:
    fn close() Unit
```

`with` accepts:

- A concrete value with an explicit `Closeable` implementation; the compiler registers that `close`.
- A contract value whose own declaration contains exactly `fn close() Unit`. This lets `File`, `ReadStream`, `WriteStream`, and test fakes work without inheritance.
- A generic parameter bounded by `Closeable` or by a contract declaring that exact signature; `close` dispatches directly.

A similarly named method without `impl Closeable`, or an unconstrained type parameter, is insufficient.

`close()` is idempotent, may suspend, and finishes the object's release before returning. Repeated or concurrent calls release the handle once. Implementations coordinate ongoing access with closure and report closed state afterward.

Expected failures belong to explicit operations such as `commit()`, `flush()`, or `finish()` returning `Result`. The automatic close returns `Unit`; an unexpected release failure is a cleanup fault.

A close failure does not skip other actions. After a failed release, leave the object unusable or quarantined; faults and remaining obligations go to the host.

User `defer` is unsupported; package custom cleanup in a `Closeable` library object. See [using with](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
