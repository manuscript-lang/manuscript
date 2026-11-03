+++
title = "Implementing Closeable"
weight = 3
+++

# Implementing Closeable

Import `Closeable` from `@std/core.ms` to name or implement it. Scope-end cleanup checks the identity of this standard contract; an unrelated same-named interface does not qualify.

```manuscript
interface Closeable:
    var fn close() Unit!
```

A binding is closed only when it holds a value whose type implements `Closeable`:

- A concrete value with an explicit `Closeable` implementation; the compiler registers that `close` when the binding is created.
- A generic parameter bounded by `Closeable`; `close` dispatches directly.

An interface value is never closed automatically, even when its interface declares `var fn close() Unit!` or is `Closeable` itself: only the concrete type's `Closeable` implementation opts in, and the interface hides it. Bind the concrete type, or call `close()` yourself.

The standard handles a caller owns are nominal types with that implementation, such as `FileHandle`, so a binding of one is checked and closed like your own. A stream interface such as `ReadStream` or `WriteStream` is never owned by its holder, because `stdout()` and a file's `writer()` share one type.

## Cloning a resource

A resource has one owner and is never copied implicitly, and it is not `Clonable`, so generic code never copies one. Where the operating system can duplicate the handle, the type has its own `clone()` that returns a `Result`: `FileHandle.clone()` and a plain TCP or Unix `Connection.clone()` return a second value with its own descriptor, which closes on its own scope end or `close()`. The copies share the underlying file or socket, so a file's position and a socket's stream are common to both. Cloning fails with an error, not a fault: a closed handle returns `Closed`, a TLS connection returns `Unsupported` because its session state cannot be shared, and running out of descriptors returns the host's failure. Nothing is reference counted. Lock guards, task, process and worker groups, temporary directories and raw terminal mode run their own cleanup once, so they have no `clone`.

## Records and collections close what they hold

A record, alternative, `Optional`, `List` or `Map` that holds a `Closeable` value is itself a resource: it moves, it cannot be cloned, and when its scope ends without anything taking it, the compiler closes what it holds. The type's own `close`, if it has one, runs first; then its parts close in reverse order of acquisition. A part whose close fails faults, because the holder has no error to return.

| Holder | Close order |
| --- | --- |
| Record | Fields, last declared first |
| Alternative | Fields of the active case, last declared first |
| `Optional` | The payload, if present |
| `List` | Elements, last index first |
| `Map` | Values, last inserted first |

A `Map` iterates in insertion order, so its close order is the reverse of the order you added the entries; no order is unspecified. Nested holders close depth first in the same way. A value derived from a resource, such as `let name = r.name`, borrows it and cannot outlive it: the checker rejects closing or changing the resource while the borrow is still used.

A holder of values that are not resources adds no code, because a `List[Int]` or a record of strings is not a resource. A part may already have closed itself, for example in a hand-written `close` that forwards to its fields; closing again is harmless because `close()` is idempotent. A generic local `List[T]` with an unconstrained `T` is not closed even when it holds resources at run time; write `T: Closeable` to opt in. Overwriting a record field, `set` or `remove` on a list, and `add` over an existing key, `remove` or `clear` on a map close the old part first, then store the new one; `xs.pop()` returns the element to a binding, which closes it. `splice` closes the elements it deletes. `fill`, `copy_within`, `merge`, and methods that return a collection or element built from the receiver's (`concat`, `take`, `slice`, `reversed`, `filter`, `find`) would make second owners of resources, so the checker rejects them on a holder of resources; move elements out with `pop` or `remove`. `Set` operations do not close yet.

A similarly named method without `impl Closeable`, or an unconstrained type parameter, is insufficient.

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
            return error(Error("gate stuck"))
        return ok(unit)

fn use_gate(fails: Bool) Unit!:
    let _gate = Gate(fails)
    return ok(unit)
```

The scope-end close behaves like `try gate.close()`: a failed close becomes the function's error, after the other bindings of the scopes it leaves have closed. This holds for every exit, including `break`, `continue` and `return`.

- If the scope is already returning an error, that error is kept and a close error after it is dropped.
- Call `close()` yourself to handle the failure; the scope end then closes the binding once more, which `close()` being idempotent makes harmless, and drops that second result, so a failure you handled is not returned again. Like any `Result`, the call needs `try`, `match` or `let _ =`.
- A close with nowhere to return its error is a fault, never silently ignored: a function that does not return `Unit!` (`Result[_, Error]`), a part of a holder, a replaced or temporary value.
- A fault or cancellation runs each close and discards its result; the failure being reported takes precedence.

A close failure does not skip other actions. After a failed release, leave the object unusable or quarantined; faults and remaining obligations go to the host.

User `defer` is unsupported; package custom cleanup in a `Closeable` library object. See [scope-end cleanup](scopes.md), [cleanup faults](cleanup-faults.md), and [operation contracts](../types/contracts.md).
