+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Import `Closeable` from `@std/core.ms` to name or implement it. `with` checks the identity of this standard contract; an unrelated same-named interface does not qualify.

```manuscript
interface Closeable:
    var def close() -> Unit
```

`with` accepts:

- A concrete value with an explicit `Closeable` implementation; the compiler registers that `close`.
- A contract value whose own declaration contains exactly `var def close() -> Unit`. This lets `File`, `ReadStream`, `WriteStream`, and test fakes work without inheritance.
- A generic parameter bounded by `Closeable` or by a contract declaring that exact signature; `close` dispatches directly.

The standard handles a caller owns are nominal types with that implementation, such as `FileHandle`, so a binding of one is checked and closed like your own. A stream interface such as `ReadStream` or `WriteStream` is never owned by its holder, because `stdout()` and a file's `writer()` share one type.

## Records and collections close what they hold

A record, alternative, `Optional`, `List` or `Map` that holds a `Closeable` value is itself a resource: it moves, it cannot be cloned, and when its scope ends without anything taking it, the compiler closes what it holds. The type's own `close`, if it has one, runs first; then its parts close in reverse order of acquisition.

| Holder | Close order |
| --- | --- |
| Record | Fields, last declared first |
| Alternative | Fields of the active case, last declared first |
| `Optional` | The payload, if present |
| `List` | Elements, last index first |
| `Map` | Values, last inserted first |

A `Map` iterates in insertion order, so its close order is the reverse of the order you added the entries; no order is unspecified. Nested holders close depth first in the same way. A value derived from a resource, such as `let name = r.name`, borrows it and cannot outlive it: the checker rejects closing or changing the resource while the borrow is still used.

A holder of values that are not resources adds no code, because a `List[Int]` or a record of strings is not a resource. A part may already have closed itself, for example in a hand-written `close` that forwards to its fields; closing again is harmless because `close()` is idempotent. A generic local `List[T]` with an unconstrained `T` is not closed even when it holds resources at run time; write `T: Closeable` to opt in. Overwriting a record field, `set` or `remove` on a list, and `add` over an existing key, `remove` or `clear` on a map close the old part first, then store the new one; `xs.pop()` returns the element to a binding, which closes it. `splice` closes the elements it deletes. `fill`, `copy_within` and `merge` would store copies of resources, so the checker rejects them on a holder of resources. `Set` operations do not close yet.

A similarly named method without `impl Closeable`, or an unconstrained type parameter, is insufficient.

`close()` is idempotent, may suspend, and finishes the object's release before returning. Repeated or concurrent calls release the handle once. Implementations coordinate ongoing access with closure and report closed state afterward.

Expected failures belong to explicit operations such as `commit()`, `flush()`, or `finish()` returning `Result`. The automatic close returns `Unit`; an unexpected release failure is a cleanup fault.

A close failure does not skip other actions. After a failed release, leave the object unusable or quarantined; faults and remaining obligations go to the host.

User `defer` is unsupported; package custom cleanup in a `Closeable` library object. See [using with](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
