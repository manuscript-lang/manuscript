+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

You can store a function in a local binding and pass it to another function. Write an anonymous function with `fn`; its type has the form `fn(value: T) -> U`.

A closure is a function value that keeps values from its surrounding scope. It captures snapshots of the bindings it uses. There is no separate function kind that consumes or transfers those captures.

```manuscript
fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int:
    return transform(value: value)

let offset = 1
let decrement = fn(value: Int) -> Int:
    return value - offset

let result = apply(value: 3, transform: decrement)
```

Function types retain parameter names. Calls through values may omit the label when the function type has exactly one parameter; multi-parameter function types require labels on every supplied argument. Labels remain part of function-type identity and compatibility even when a call omits one. Calls have the same suspension and evaluation rules as declared functions. Inferred immutable copies retain [default arguments](declarations-and-calls.md#default-arguments); explicit function types require all parameters.

## Function type compatibility

Parameter names, declaration order, parameter types, and result type are all part of function-type identity. Compatibility is invariant: a different label, reordered signature, or different result type requires an explicit adapter function. Caller-written argument order may vary without changing the function's declared type.

```manuscript
fn subtract_one(amount: Int) -> Int:
    return amount - 1

fn adapt() -> Unit:
    # Rejected: amount and value are different function-type labels.
    let invalid: fn(value: Int) -> Int = subtract_one

    let renamed = fn(value: Int) -> Int:
        return subtract_one(amount: value)
    let result = apply(value: 3, transform: renamed)
```

The rejected binding is a negative example; removing it leaves a valid function. Anonymous functions require explicit parameter and result types and an inline or indented body, exactly as specified in the [grammar](../basics/grammar.md). An annotation on the receiving variable does not omit those signatures. A generic function must be instantiated before it is stored as a value; `identity[Int]` is a function value, while a bare polymorphic `identity` is not. Bound method values have the operation's function type with the receiver already bound and excluded from the parameter list.

An anonymous function forms its own function boundary for `return`, `try`, `break`, and `continue`. Its control-flow exits cannot exit the containing function or loop. Capture and sharing behavior remains governed by the separate contracts below.

## Snapshot captures

A closure remembers the current value of each local binding it uses:

```manuscript
fn make_headline() -> fn() -> String:
    var subject = "Weekly update"
    let headline = fn() -> String:
        return subject
    subject = "Launch announcement"
    return headline
# make_headline()() returns "Weekly update".
```

Reassignment changes the local binding, not the captured value. Assigning to a captured outer binding is rejected.

Capturing a record or collection keeps a reference to the same object. Changes to that object remain visible:

```manuscript
import List from "@std/collections.ms"

fn tag_count() -> Int:
    let tags = ["docs"]
    let count = fn() -> Int:
        return tags.length()
    tags.append("release")
    return count()
# tag_count() returns 2.
```

Use `.clone()` before capturing if you need independent outer storage. Nested references remain shared. Coordinate concurrent reads and writes with [Synchronized](../../concurrency/synchronization.md#synchronized). A bound method retains its receiver by the same reference rules.

## Resource captures

Open a resource inside the callback that uses it:

```manuscript
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

fn notes_reader(path: String) -> fn() -> Result[Bytes, FileSystemError]:
    return fn() -> Result[Bytes, FileSystemError]:
        with file = try filesystem().open(path: path, flags: "r", mode: 0):
            return file.read_file(max_bytes: 1048576)
```

`notes_reader("notes.txt")` returns a callback. Each call opens, reads, and closes its own file.

Capturing an already-open file keeps the same handle; it does not delay its `with` cleanup. Calling `FileHandle.read_file` after that block returns `FileSystemError.Closed`. Passing a resource through a parameter or storing it in a record has the same lifetime rule.

## Concurrent invocation

Concurrency APIs accept ordinary functions. Function parameters, returned functions, function fields, and generic forwarding work exactly as local function values do. See [function sharing](../../concurrency/sharing.md#function-values). A shared resource can still be closed before invocation.

Capture request-data snapshots and application services for scheduled work, then acquire job resources within that operation. Keep a TaskGroup scope inside the resources its tasks use. The group cancels and joins at scope exit before the enclosing resources close, unless a resource is explicitly closed elsewhere.

See [task groups](../../concurrency/task-groups.md), [scheduling work](../../concurrency/scheduling.md), and [reference sharing](../../concurrency/sharing.md).
