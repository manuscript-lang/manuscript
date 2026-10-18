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

Function types retain parameter names. Calls through values accept positional, labeled, and mixed arguments under the ordinary [call rules](declarations-and-calls.md#argument-names). Labels remain part of function-type identity and compatibility even when a call omits one. A contextual anonymous function adopts those labels while keeping its own local parameter names. Calls have the same suspension and evaluation rules as declared functions. Inferred immutable copies retain [default arguments](declarations-and-calls.md#default-arguments); explicit function types require all parameters.

## Function type compatibility

Callable argument labels, declaration order, parameter types, and result type are all part of function-type identity. Compatibility is invariant: a different label, reordered signature, or different result type requires an explicit adapter function. Caller-written argument order may vary without changing the function's declared type.

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

The rejected binding is a negative example; removing it leaves a valid function. An anonymous function may omit parameter types when its context supplies them: an argument, annotation, field, collection element, or return type. Parameters correspond by position and keep invariant types, and local names may differ from the context's labels: `let increment: fn(value: Int) -> Int = fn(item): item + 1` is called as `increment(value: 3)`. An already bound function keeps its labels. An omitted result type comes from context or, when all inputs are known, from the body: returns must share one exact type, fallthrough contributes `Unit`, and `Never` contributes nothing. Without context, callbacks need parameter annotations. An inline body returns its value; multiline bodies use `return` ([grammar](../basics/grammar.md)). A generic function must be instantiated to be a value: `identity[Int]` is one, bare `identity` is not. A bound method value has the operation's function type with the receiver already bound.

An anonymous function forms its own function boundary for `return`, `try`, `break`, and `continue`. Its control-flow exits cannot exit the containing function or loop. Capture and sharing behavior remains governed by the separate contracts below.

## Snapshot captures

A closure remembers the current value of each local binding it uses:

```manuscript
fn make_headline() -> fn() -> String:
    var subject = "Weekly update"
    let headline = fn():
        return subject
    subject = "Launch announcement"
    return headline
# make_headline()() returns "Weekly update".
```

Reassignment changes the local binding, not the captured value. Assigning to a captured outer binding is rejected.

Capturing a record or collection keeps a reference to the same object. Changes to that object remain visible:

```manuscript

fn tag_count() -> Int:
    let tags = ["docs"]
    let count = fn():
        return tags.length()
    tags.append("release")
    return count()
# tag_count() returns 2.
```

Use `.clone()` before capturing if you need independent outer storage. Nested references remain shared. Coordinate concurrent reads and writes with Synchronized. A bound method retains its receiver by the same reference rules.

## Resource captures

Open a resource inside the callback that uses it:

```manuscript
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) -> fn() -> Result[Bytes, FileSystemError]:
    return fn():
        with file = try filesystem().open(path: path, flags: "r", mode: 0):
            return file.read_file(max_bytes: 1048576)
```

`notes_reader("notes.txt")` returns a callback. Each call opens, reads, and closes its own file.

Capturing an already-open file keeps the same handle; it does not delay its `with` cleanup. Calling `FileHandle.read_file` after that block returns `FileSystemError.Closed`. Passing a resource through a parameter or storing it in a record has the same lifetime rule.

## Concurrent invocation

Concurrency APIs accept ordinary functions. Function parameters, returned functions, function fields, and generic forwarding work exactly as local function values do. See function sharing. A shared resource can still be closed before invocation.

Capture request-data snapshots and application services for scheduled work, then acquire job resources within that operation. Keep a TaskGroup scope inside the resources its tasks use. The group cancels and joins at scope exit before the enclosing resources close, unless a resource is explicitly closed elsewhere.

See task groups, scheduling work, and reference sharing.

## Contextual callback inference

```manuscript

fn names() -> List[String]:
    return [1, 2].map(fn(value): value.toString())
```

Here the list supplies `Int` for `value` and the expected `List[String]` supplies the callback result; without it, the body determines `String`. Other arguments may establish callback inputs in any written order, and callbacks are revisited as context becomes known; runtime evaluation order is unchanged. An unambiguous expected call result may establish generic arguments first ([generic inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type (which `try` uses) while the body determines the success type. If neither determines it, add an explicit specialization or annotation.
