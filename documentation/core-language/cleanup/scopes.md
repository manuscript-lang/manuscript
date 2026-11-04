+++
title = "Scope-end cleanup"
weight = 1
+++

# Scope-end cleanup

A `let` or `var` that holds a resource closes it when its scope ends. There is no extra syntax: bind the value and use it.

This function reads a file and closes its handle on every exit:

```manuscript
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn read_head(path: String) Bytes?!:
    let file = try open(path, flags: "r", mode: 0)
    return file.read(max_bytes: 4096)
```

`open` returns an owned `FileHandle`; `read` returns bytes or `none` at end of file, with an error on failure.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the rest of the scope.
5. Close the registered resource when execution leaves the scope.

Cleanup runs on every exit: end of scope, `break`, `continue`, `return`, `try` propagation, fault, or cancellation. Nested scopes close inner to outer, and bindings in one scope close last declared first.

## Which values are closed?

A concrete type opts in through an implementation of the standard `Closeable` interface. A value of the standard `Closeable` interface also closes automatically. An unrelated interface does not acquire cleanup merely by declaring a method named `close`; retain a concrete owner or close it explicitly. Records, alternatives, optionals and collections close the resource parts they own, including in generic instances. See [Closeable](closeable.md) for the exact checks and close order.

## Control the lifetime

A binding is closed unless something takes the resource from it. Returning it, passing it to a moving parameter, storing it, or capturing it in a closure that outlives the scope moves it to a new owner, which closes it instead. A resource acquired in a loop closes at the end of that iteration.

To close earlier than the end of the scope, declare the binding with `var` and call `close()`. Close is idempotent, so the scope-end close that follows is harmless; the later statements still see a closed resource, so do not use it afterwards. Closing a file early is a common case; handle the `Result` with `try` or `let _ =`.

```manuscript
var file = try open(path, flags: "r", mode: 0)
let head = try file.read_lines(max_lines: 1)
let _ = file.close()
slow_work(head)
```

`close` returns `Unit!`, so a failed close is returned or faults rather than lost; flush buffered streams first (`try output.flush().wait()`) so delivery errors can be handled. `ms lint` reports **MSL114** when a closed-at-scope-end resource has an uncalled `flush`, `sync` or `commit`. There are no enter or error-suppression hooks.
