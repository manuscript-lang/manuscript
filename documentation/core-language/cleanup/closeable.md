+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Implement `Closeable` when your type owns a resource that must be released at scope end. Import it from `@std/core.ms` to name or implement it. Scope-end cleanup checks the identity of this standard contract; an unrelated same-named interface does not qualify.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
interface Closeable {
    move fn close() Void!
}
```

For a type that satisfies `Closeable`, cleanup calls its declared operation:

- A concrete value whose type has an own `fn move close() Void!` ([shape](../types/contracts.md#satisfying-an-interface)); the compiler registers that `close` when the binding is created.
- A generic parameter bounded by `Closeable`; `close` dispatches directly.

A value typed as the standard `Closeable` interface owns its concrete value and closes it automatically. An unrelated interface merely declaring `move fn close() Void!` does not opt into cleanup; retain a concrete owner or call its `close()` explicitly.

The standard handles a caller owns are nominal types with that method, such as `FileHandle`, so a binding of one is checked and closed like your own. `ReadStream[T]` and `WriteStream[T]` are types with that `close`, so a binding of one closes at scope end. Closing a built-in descriptor write stream waits until its queued bytes are handed to the descriptor, then releases it, even if the wait fails; the failure is returned. A custom stream calls its source or sink’s `close`, which may wait. Call [`flush()`](scopes.md#close-a-resource-explicitly) before closing to handle a drain failure or observe the destination’s backpressure.

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

A `Map` iterates in insertion order, so its values close in the reverse of the order you added the entries. Nested holders close depth first in the same way. A value derived from a resource, such as `name := r.name`, borrows it and cannot outlive it: the checker rejects closing or changing the resource while the borrow is still used.

A holder of values that are not resources adds no code: a `List[Int]`, or a type whose fields are strings, is not a resource. A generic holder such as `List[T]` closes its resource parts, and the compiler picks cleanup for each concrete instance, so an instance holding only plain data adds no close calls. A hand-written `close` may close a field itself (`self.input.close()?`) to return the field's error or to fix the order; the compiler still closes the parts after your `close` returns, so a part's own `close` must tolerate that repeat.

- **Replacing or removing closes the old part first.** This covers overwriting a field, `set` or `remove` on a list, and `add` over an existing key, `remove` or `clear` on a map. `splice` closes the elements it deletes.
- **`pop` hands the element out.** `xs.pop()` returns the element to a binding, which closes it. To take an element out of a list, use `pop`.
- **Some methods are rejected on a holder of resources.** `fill`, `copy_within`, `merge`, and methods that return a collection or element built from the receiver's (`concat`, `take`, `slice`, `reversed`, `filter`, `find`) would make second owners, so the checker refuses them.
- **No sets.** A `Set` cannot hold resources because its elements must be `Hashable`.

A similarly named method whose signature is not `fn move close() Void!` does not opt a concrete type into cleanup.

`close` takes its receiver (`fn move`): the value is gone after the call, so the compiler rejects a later use or a second `close()` of the same binding, and the scope-end close does not run for a binding you closed. `close()` may suspend and finishes the object's release before returning. An implementation must coordinate access that is still in progress when `close()` runs. Inside a `close` body, `self` may be changed (record that you released), and `self.field.close()` is a partial move like any other: a close body closes each resource field once, by value. Only the owner can close: a value you only borrow (a plain or `var` parameter) cannot be closed or passed to a `move` position, so take it with `move` when the function closes it.

To close one part of a holder that stays in use (a connection's output side), take the part out and put a new one in the next statement: `part := conn.output` then `conn.output = ...`. Without the refill the checker rejects the take. A stream's `end()` is the standard half close: it closes the source or sink now and leaves the stream ended, so the holder keeps its other parts and closes them at the end.

## A close returns a Result

`close()` returns `Void!`, which is `Result[Void, Error]`: releasing a resource can fail, and the failure is a value. A type whose release cannot fail returns `ok()`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Closeable from "@std/core.ms"

type Gate {
    fails Bool
}

fn move Gate.close() Void! {
    if self.fails {
        self.fails = false
        return error(Error("gate stuck"))
    }
}

fn use_gate(fails Bool) Void! {
    _gate := Gate(fails)
}
```

This example reports the release failure once.

The scope-end close behaves like `gate.close()?`: a failed close becomes the function's error, after the other bindings of the scopes it leaves have closed. This holds for every exit, including `break`, `continue` and `return`.

- If the scope is already returning an error, that error is kept and a close error after it is dropped.
- Call `close()` yourself to handle the failure. The call moves the binding, so the scope end does not close it again, and a failure you handled is not returned twice. Like any `Result`, the call needs `?`, `if v := x` or `void`.
- A close with nowhere to return its error is a fault, never silently ignored: a function that does not return `Result[_, Error]`, a part of a holder, a replaced or temporary value.
- A fault or cancellation runs each close and discards its result; the failure being reported takes precedence.

A close failure does not skip other actions. After a failed release, leave the object unusable or quarantined; faults and remaining obligations go to the host.

User `defer` is unsupported; package custom cleanup in a `Closeable` library object. See [scope-end cleanup](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
