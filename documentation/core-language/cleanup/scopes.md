+++
title = "Scope-end cleanup"
weight = 1
+++

# Scope-end cleanup

A `let` or `var` that holds a resource closes it when its scope ends. There is no extra syntax: bind the value and use it.

This program reads a chunk from a file and closes its handle on every exit. Save as `read-head.ms`, create `notes.txt` with `first` and `second` on separate lines with a final newline, and run `ms run read-head.ms`. It prints `Read 13 bytes`:

<!-- manuscript-example: {"mode":"run","files":{"notes.txt":"first\nsecond\n"},"stdout":"Read 13 bytes\n","filename":"read-head.ms"} -->
```manuscript
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn read_head(path: String) Bytes?!:
    let file = try open(path, flags: "r", mode: 0)
    return file.read(max_bytes: 4096)

export fn main() Int:
    let outcome = read_head("notes.txt").map_error(fn cause: print(cause.message))
    if let head = outcome:
        if let bytes = head:
            print("Read {bytes.length()} bytes")
        else:
            print("End of file")
        return 0
    return 1
```

`open` returns an owned `FileHandle`; `read` returns bytes or `none` at end of file, with an error on failure. The function returns the data, not the handle. Once the read's return value is ready, the scope closes the file before delivering that value to the caller. If opening fails, `try` returns the error before a file binding exists.

`FileHandle.read` is declared as an ordinary `fn`, so a `let` handle can read even though the host's file position advances. Explicit `close` is a `var fn` and needs a `var` binding. Follow the API's declared signature rather than inferring a mutation requirement from the operation's name.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the rest of the scope.
5. Close the registered resource when execution leaves the scope.

Cleanup runs on every exit: end of scope, `break`, `continue`, `return`, `try` propagation, fault, or cancellation. Nested scopes close inner to outer, and bindings in one scope close last declared first.

The registration belongs to a successful acquisition. If a factory acquires a native handle but cannot deliver it because of an error or cancellation, the factory must release it. After delivery, the new owner takes over that responsibility. This prevents a gap between acquiring a handle and registering its cleanup.

## Which values are closed?

A concrete type opts in through an implementation of the standard `Closeable` interface. A value of the standard `Closeable` interface also closes automatically. An unrelated interface does not acquire cleanup merely by declaring a method named `close`; retain a concrete owner or close it explicitly. Records, enums, optionals and collections close the resource parts they own, including in generic instances. See [Closeable](closeable.md) for the exact checks and close order.

## Control the lifetime

A binding is closed unless something takes the resource from it. Returning it, passing it to a moving parameter, storing it, or capturing it in a closure that outlives the scope moves it to a new owner, which closes it instead. A resource acquired in a loop closes at the end of that iteration.

To close earlier than the end of the scope, declare the binding with `var` and call `close()`. Close is idempotent, so the scope-end close that follows is harmless; the later statements still see a closed resource, so do not use it afterwards. Closing a file early is a common case; propagate the close failure with `try`, or inspect the Result if the caller can recover. Save this complete program as `read-notes.ms`, create `notes.txt` containing `first` and `second` on separate lines with a final newline, and run `ms run read-notes.ms`:

<!-- manuscript-example: {"mode":"run","files":{"notes.txt":"first\nsecond\n"},"stdout":"Read 13 bytes; file is closed\n","filename":"read-notes.ms"} -->
```manuscript
import open from "@std/os/fs.ms"

fn read_notes() Unit!:
    var file = try open("notes.txt", flags: "r", mode: 0)
    let contents = try file.read_file(max_bytes: 1048576)
    try file.close()
    print("Read {contents.length()} bytes; file is closed")
    return ok(unit)

export fn main() Int:
    let outcome = read_notes().map_error(fn cause: print(cause.message))
    if let _completed = outcome:
        return 0
    return 1
```

The program prints `Read 13 bytes; file is closed`. The explicit close completes before the next operation. `read_file` reads the remaining file up to its byte limit; a limit is a cap that can fail, not a request to silently truncate input.

`close` returns `Unit!`, so a failed close is returned or faults rather than lost; flush buffered streams first (`try output.flush().wait()`) so delivery errors can be handled. `ms lint` reports **MSL114** when a closed-at-scope-end resource has an uncalled `flush`, `sync` or `commit`. There are no enter or error-suppression hooks.
