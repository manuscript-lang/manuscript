+++
title = "Using with"
weight = 1
+++

# Using with

Use `with` to acquire a resource and close it when an indented block ends. The name introduced by `with` cannot be reassigned.

```manuscript
with file = try files.open(path: "data.txt"):
    let chunk = try file.read(max_bytes: 4096)
```

This fragment belongs inside a function returning `Result[U, IoError]`. The function receives `files` as an explicit capability. `Files.open` returns a shared File view. The read result is `Optional[Bytes]`: match it to distinguish bytes from end-of-input.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the block.
5. Close the registered resource when execution leaves the block.

Cleanup runs for every exit: reaching the end, `break`, `continue`, `return`, an error forwarded by `try`, a fault, or cancellation. Nested scopes close from inner to outer.

## Which values can use with?

The compiler must be able to identify a valid close operation:

| Value's type | Required evidence |
| --- | --- |
| Concrete type | An explicit implementation of standard `Closeable`. |
| Contract view | A declared `fn close() -> Unit` operation. |
| Generic parameter | A bound proving one of those operations. |

See [Closeable](closeable.md) for the exact checks.

## Keep the lifetime tied to the block

A resource acquired inside a loop closes at the end of that iteration. Returning it or capturing it in a closure does not remove its registered cleanup. An ordinary `let` binding does not register cleanup.

The file, transaction, or scheduler supplies its own close behavior. `with` adds no custom enter hook or error-suppression hook.
