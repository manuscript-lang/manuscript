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

The rejected binding is a negative example; removing it leaves a valid function. Anonymous functions may omit parameter types when a surrounding function type supplies them. The context may come from an argument, binding annotation, field, collection element, or return type. Local parameter names may differ from the context's labels; parameters correspond by declaration order and retain invariant types. For example, `let increment: fn(value: Int) -> Int = fn(item): item + 1` uses `item` inside the body and is called as `increment(value: 3)`. This applies to directly contextual anonymous functions, including generic callback arguments; an already bound function value retains its existing labels. An omitted result type comes from a known context, or is inferred from the body when all input types are known. Without a result context, returns must have one exact type; normal fallthrough contributes `Unit`, and `Never` contributes no competing value. Standalone callbacks still need parameter annotations when no context provides their types. An inline expression body returns its value; multiline bodies use explicit `return`. See the [grammar](../basics/grammar.md). A generic function must be instantiated before it is stored as a value; `identity[Int]` is a function value, while a bare polymorphic `identity` is not. Bound method values have the operation's function type with the receiver already bound and excluded from the parameter list.

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

Here the list supplies `Int` for `value`, and the expected `List[String]` result supplies `String` for the callback result. Without that expected result, the body can determine `String`. Other supplied arguments may establish callback inputs regardless of their written order; callbacks are revisited as their input context becomes known. This checking order does not change runtime evaluation order. An unambiguous expected outer call result may establish missing generic arguments before callback checking; see [generic inference](../types/generics.md#inference-from-arguments). Known parts of a Result context supply its error type while the callback body determines its generic success type. `try` uses that Result error context. If neither the outer context nor the callback body determines the success type, an explicit specialization or annotation is still needed.
