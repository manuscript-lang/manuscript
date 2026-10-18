+++
title = "Using with"
weight = 1
+++

# Using with

`with` acquires a resource and closes it when its indented block ends. The introduced name cannot be reassigned.

```manuscript
with file = try files.open("data.txt"):
    let chunk = try file.read(max_bytes: 4096)
```

This sits inside a function returning `Result[U, IoError]` that receives `files` as a capability. `Files.open` returns a shared File view; `read` returns `Optional[Bytes]`.

## What happens, step by step

1. Evaluate the initializer once. Here, that means opening the file.
2. If initialization fails, leave through the initializer's error or fault path. No close action has been registered.
3. If initialization succeeds, register the resource's close operation before the next cancellation checkpoint.
4. Run the block.
5. Close the registered resource when execution leaves the block.

Cleanup runs on every exit: end of block, `break`, `continue`, `return`, `try` propagation, fault, or cancellation. Nested scopes close inner to outer.

## Which values can use with?

The compiler needs a valid close operation:

| Value's type | Required evidence |
| --- | --- |
| Concrete type | An explicit implementation of standard `Closeable`. |
| Contract view | A declared `fn close() Unit` operation. |
| Generic parameter | A bound proving one of those operations. |

See [Closeable](closeable.md) for exact checks.

## Keep the lifetime tied to the block

A resource acquired in a loop closes at the end of that iteration. Returning it or capturing it in a closure keeps its cleanup. An ordinary `let` registers none. `with` adds no enter or error-suppression hooks.
