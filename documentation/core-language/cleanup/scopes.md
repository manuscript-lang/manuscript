+++
title = "Scope-end cleanup"
weight = 1
aliases = ["/core-language/cleanup/resource-release/", "/core-language/cleanup/exit-order/"]
+++

# Scope-end cleanup

A `:=` or `var` that holds a resource closes it when its scope ends. There is no extra syntax: bind the value and use it.

This function reads a file and closes its handle on every exit:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import (
    Bytes from "@std/bytes.ms",
    open from "@std/os/fs.ms",
)

fn read_head(path String) Bytes?! {
    file := open(path)?
    return file.read(max_bytes: 4096)
}
```

`open` returns an owned `FileHandle`; `read` returns bytes or `null` at end of file, with an error on failure.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the rest of the scope.
5. Close the registered resource when execution leaves the scope.

Cleanup runs on every exit: the end of the scope, `break`, `continue`, `return`, `?` propagation, fault, or cancellation. Nested scopes close inner to outer, and bindings in one scope close last declared first.

## Which values are closed?

A concrete type opts in through an implementation of the standard `Closeable` interface. A value of the standard `Closeable` interface also closes automatically. An unrelated interface does not acquire cleanup merely by declaring a method named `close`; retain a concrete owner or close it explicitly. Types, enums, optionals and collections close the resource parts they own, including in generic instances. See [Closeable](closeable.md) for the exact checks and close order.

## Control the lifetime

A binding is closed unless something takes the resource from it. Returning it, passing it to a moving parameter, storing it, or capturing it in a closure that outlives the scope moves it to a new owner, which closes it instead. A resource acquired in a loop closes at the end of that iteration.

To close earlier than the end of the scope, call `close()`. `close` is a `move` method, so the call moves the binding: the scope end does not close it again, and a later use of the name is a use after move. Closing a file early is a common case; handle the `Result` with `?` or `void`.

<!-- manuscript-example: {"mode":"fragment","context":"import open from \"@std/os/fs.ms\"\n\nfn slow_work(head List[String]) Void {\n    return\n}","given":["path String"]} -->
```manuscript
file := open(path)?
head := file.read_lines(max_lines: 1)?
void file.close()
slow_work(head)
```

`close` returns `Void!`, so a failed close is returned or faults rather than lost. Flush buffered streams first (`output.flush()?`) so delivery errors can be handled.

`ms lint` reports **MSL114** when a resource closed at scope end has an uncalled `flush` or `commit`. A `FileHandle` is not reported: its writes go straight to the OS, close does not need a flush, and `sync` (fsync) only adds durability. There are no enter or error-suppression hooks.

## Close a resource explicitly

Usually, let scope-end cleanup close a file, socket or stream. Close explicitly when the next operation should begin only after the resource is released, or when you need to handle a close error.

Flush before closing when you need the destination to catch up or need to handle a flush failure:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import WriteStream from "@std/io/io.ms"

fn finish(move output WriteStream[String]) Void! {
    output.flush()?
    return output.close()
}
```

`flush()` follows the destination's backpressure rule:

- **Files and sockets** wait for queued bytes to drain.
- **A pipe** waits until its queue is at or below `capacity`, which need not be empty. Closing a built-in pipe writer releases that writing end without waiting for the reader.
- **Standard output** is buffered. `stdout().flush()` writes the buffer and returns the first failed write (a full disk, a closed descriptor) as an error, and `write` returns it once it is known. A program that would exit 0 after losing output exits 1 with a message on standard error. A broken pipe is not an error. `print` has no result and reports nothing itself.
- **A custom sink** supplies its own close behavior and may wait.

The `close()` moves the stream, so nothing closes it again.

To confirm that your work succeeded, call the operation that reports it. `close()` returns a `Result`, and a failed scope-end close is returned or faults. Explicit commit, finish, and flush operations report expected errors with `Result`. A value that is not a resource, such as a `List[Int]` or a closure that captures none, adds no close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery, and a binding registers its close right after the initializer succeeds, before cancellation can unwind it. See [Closeable](closeable.md).

## Cleanup order

On scope exit, inner resources close before outer ones, and the bindings of one scope close last declared first. A borrow registers no extra close. A type or collection that owns resources closes its owned parts; see [holder cleanup](closeable.md#types-and-collections-close-what-they-hold).

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Call registered `close()` methods in reverse registration/nesting order.
3. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault can suppress a pending return or domain error; see [cleanup failures](cleanup-faults.md) for fault selection.

Returning an owned resource transfers its cleanup duty to the caller: the exiting scope does not close the moved value. Moving it into a field, collection or escaping closure likewise transfers responsibility to the new owner. A borrowed part cannot escape a local owner that is about to close; returning a borrow of an argument keeps the caller responsible for that owner.

## Observe the order

Save as `cleanup.ms` and run `ms run cleanup.ms`. The small resource below prints when it closes:

<!-- manuscript-example: {"mode":"run","stdout":"work\nclose second\nclose first\n"} -->
```manuscript
import Closeable from "@std/core.ms"

type Tracked {
    name String
    closed Bool = false
}

fn move Tracked.close() Void! {
    if not self.closed {
        self.closed = true
        print(f"close {self.name}")
    }
}

fn work() Void! {
    _first := Tracked("first")
    _second := Tracked("second")
    print("work")
}

fn main() Void! {
    return work()
}
```

```text
work
close second
close first
```

Declare dependencies in an outer scope, or before the resources that use them, so they close after the resources that use them. See [fault selection](cleanup-faults.md).
