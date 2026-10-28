+++
title = "Scope-end cleanup"
weight = 1
+++

# Scope-end cleanup

A `let` or `var` that holds a resource closes it when its scope ends. There is no extra syntax: bind the value and use it.

```manuscript
let file = try files.open("data.txt")
let chunk = try file.read(max_bytes: 4096)
```

This sits inside a function returning `Result[U, IoError]` that receives `files` as a capability. `Files.open` returns a shared File view; `read` returns `Optional[Bytes]`. The file closes when the function returns, whichever path it takes.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the rest of the scope.
5. Close the registered resource when execution leaves the scope.

Cleanup runs on every exit: end of scope, `break`, `continue`, `return`, `try` propagation, fault, or cancellation. Nested scopes close inner to outer, and bindings in one scope close last declared first.

## Which values are closed?

The compiler needs a valid close operation:

| Value's type | Required evidence |
| --- | --- |
| Concrete type | An explicit implementation of standard `Closeable`. |
| Contract view | A declared `def close() -> Unit` operation. |
| Generic parameter | A bound proving one of those operations. |

A holder closes its parts: a record, an alternative, an `Optional`, a `List` or a `Map` of resources closes each one it holds. See [Closeable](closeable.md) for exact checks.

## Control the lifetime

A binding is closed unless something takes the resource from it. Returning it, passing it to a consuming parameter, storing it, or capturing it in a closure that outlives the scope moves it to a new owner, which closes it instead. A resource acquired in a loop closes at the end of that iteration.

To close earlier than the end of the scope, declare the binding with `var` and call `close()`. Close is idempotent, so the scope-end close that follows is harmless; the later statements still see a closed resource, so do not use it afterwards. A lock guard is a common case: `guard.close()` ends the critical section early.

```manuscript
var guard = lock(counter)
guard.value += 1
guard.close()
slow_work()
```

`close` returns `Unit`, so a failed flush is invisible: call the fallible method (`try x.flush()`) first. `ms lint` reports **MSL114** when a closed-at-scope-end resource has an uncalled `flush`, `sync` or `commit`. There are no enter or error-suppression hooks.
