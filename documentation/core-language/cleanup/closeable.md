+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Implement `Closeable` when your type owns a resource that must be released at scope end. Import it from `@std/core.ms` to name or implement it. Scope-end cleanup checks the identity of this standard contract; an unrelated same-named interface does not qualify.

```manuscript
interface Closeable:
    var fn close() Unit!
```

For a type that implements `Closeable`, cleanup calls its declared operation:

- A concrete value with an explicit `Closeable` implementation; the compiler registers that `close` when the binding is created.
- A generic parameter bounded by `Closeable`; `close` dispatches directly.

A value typed as the standard `Closeable` interface owns its concrete value and closes it automatically. An unrelated interface merely declaring `var fn close() Unit!` does not opt into cleanup; retain a concrete owner or call its `close()` explicitly.

The standard handles a caller owns are nominal types with that implementation, such as `FileHandle`, so a binding of one is checked and closed like your own. `ReadStream[T]` and `WriteStream[T]` are types that implement `Closeable`, so a binding of one closes at scope end. Built-in descriptor streams hand queued writes to the runtime on close; they do not wait for delivery. A custom stream calls its source or sink’s `close`, which may wait. Use [`flush()`](scopes.md#close-a-resource-explicitly) to observe the destination’s backpressure or drain result before closing.

## Cloning a resource

A resource has one owner and is never copied implicitly. It is not `Clonable`, so generic copying operations reject it. `FileHandle.clone()` is a separate, fallible operation that duplicates the operating-system descriptor. Each handle closes independently, but both share the file position. A closed handle returns `"EBADF"`; descriptor exhaustion returns the host's error.

A `Connection` has no `clone()`; its input and output streams own their respective ends. Temporary directories and raw terminal mode also have no `clone()`.

## Types and collections close what they hold

A type, enum, `Optional`, `List` or `Map` that holds a `Closeable` value is itself a resource: it moves, it cannot be cloned, and when its scope ends without anything taking it, the compiler closes what it holds. The type's own `close`, if it has one, runs first; then its parts close in the order below. A part whose close fails faults, because the holder has no error to return.

| Holder | Close order |
| --- | --- |
| Type | Fields, last declared first |
| Alternative | Fields of the active case, last declared first |
| `Optional` | The payload, if present |
| `List` | Elements, last index first |
| `Map` | Values, last inserted first |

A `Map` iterates in insertion order, so its close order is the reverse of the order you added the entries; no order is unspecified. Nested holders close depth first in the same way. A value derived from a resource, such as `name := r.name`, borrows it and cannot outlive it: the checker rejects closing or changing the resource while the borrow is still used.

A holder of values that are not resources adds no code, because a `List[Int]` or a type whose fields are strings is not a resource. A part may already have closed itself, for example in a hand-written `close` that forwards to its fields; closing again is harmless because `close()` is idempotent. A generic holder such as `List[T]` also closes its resource parts: lowering selects cleanup for each concrete instance, and an instance holding only plain data adds no close calls. Overwriting a field, `set` or `remove` on a list, and `add` over an existing key, `remove` or `clear` on a map close the old part first, then store the new one; `xs.pop()` returns the element to a binding, which closes it. `splice` closes the elements it deletes. `fill`, `copy_within`, `merge`, and methods that return a collection or element built from the receiver's (`concat`, `take`, `slice`, `reversed`, `filter`, `find`) would make second owners of resources, so the checker rejects them on a holder of resources; move a list element out with `pop`. `remove` closes the removed element. A `Set` cannot hold resources because its elements must be `Hashable`.

A similarly named method without `impl Closeable` does not opt a concrete type into cleanup.

`close()` is idempotent, may suspend, and finishes the object's release before returning. Repeated or concurrent calls release the handle once. Implementations coordinate ongoing access with closure and report closed state afterward.

## A close returns a Result

`close()` returns `Unit!`, which is `Result[Unit, Error]`: releasing a resource can fail, and the failure is a value. A type whose release cannot fail returns `ok(unit)`.

```manuscript
import Closeable from "@std/core.ms"

type Gate:
    fails: Bool

impl Closeable for Gate:
    var fn close() Unit!:
        if self.fails:
            self.fails = false
            return error(Error("gate stuck"))

fn use_gate(fails: Bool) Unit!:
    _gate := Gate(fails)
```

This example reports the release failure once; a later close succeeds without repeating the release attempt.

The scope-end close behaves like `try gate.close()`: a failed close becomes the function's error, after the other bindings of the scopes it leaves have closed. This holds for every exit, including `break`, `continue` and `return`.

- If the scope is already returning an error, that error is kept and a close error after it is dropped.
- Call `close()` yourself to handle the failure; the scope end then closes the binding once more, which `close()` being idempotent makes harmless, and drops that second result, so a failure you handled is not returned again. Like any `Result`, the call needs `try`, `if v := x` or `_ :=`.
- A close with nowhere to return its error is a fault, never silently ignored: a function that does not return `Result[_, Error]`, a part of a holder, a replaced or temporary value.
- A fault or cancellation runs each close and discards its result; the failure being reported takes precedence.

A close failure does not skip other actions. After a failed release, leave the object unusable or quarantined; faults and remaining obligations go to the host.

User `defer` is unsupported; package custom cleanup in a `Closeable` library object. See [scope-end cleanup](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
