+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

Store a function in a binding or pass it as an argument. Anonymous functions use `fn`; the type is `fn(value: T) U`. A closure captures snapshots of the bindings it uses.

```manuscript
fn apply(value: Int, transform: fn(value: Int) Int) Int:
    return transform(value: value)

let offset = 1
let decrement = fn(value: Int) Int:
    return value - offset

let result = apply(value: 3, transform: decrement)
```

Function types keep parameter names. Calls through values follow the [call rules](declarations-and-calls.md#argument-names), with the same suspension and evaluation as declared functions. A contextual anonymous function adopts the context's labels but keeps its own local names. Inferred immutable copies keep [default arguments](declarations-and-calls.md#default-arguments); explicit function types require all parameters.

## Function type compatibility

Labels, parameter order, parameter types, and result type are all part of function-type identity, and compatibility is invariant. A mismatch needs an explicit adapter function.

```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

fn adapt() Unit:
    # Rejected: amount and value are different function-type labels.
    let invalid: fn(value: Int) Int = subtract_one

    let renamed = fn(value: Int) Int:
        return subtract_one(amount: value)
    let result = apply(value: 3, transform: renamed)
```

An anonymous function may omit parameter types when context supplies them (argument, annotation, field, collection element, or return type). Parameters match by position; local names may differ from the context's labels: `let increment: fn(value: Int) Int = fn(item): item + 1` is called as `increment(value: 3)`.

- An omitted result type comes from context or the body: returns must share one exact type, fallthrough adds `Unit`, `Never` adds nothing.
- Without context, callbacks need parameter annotations.
- A generic function must be instantiated to be a value: `identity[Int]`, not bare `identity`.
- A bound method value has the operation's function type with the receiver bound.
- An anonymous function is its own boundary for `return`, `try`, `break`, and `continue`.

## Snapshot captures

A closure remembers the current value of each local binding it uses:

```manuscript
fn make_headline() fn() String:
    var subject = "Weekly update"
    let headline = fn():
        return subject
    subject = "Launch announcement"
    return headline
# make_headline()() returns "Weekly update".
```

Reassignment changes the local binding, not the captured value. Assigning to a captured outer binding is rejected.

A closure that is only called in the function that made it borrows what it captures, so the captured variable cannot change while the closure is still used. Make the changes first, then create the closure:

```manuscript

fn tag_count() Int:
    var tags = ["docs"]
    tags.append("release")
    let count = fn():
        return tags.length()
    return count()
# tag_count() returns 2.
```

A closure that is returned or stored owns what it captures instead, so it cannot change a captured variable. Use `.clone()` before capturing to keep using the original. A bound method keeps its receiver by the same rules.

## Resource captures

Open a resource inside the callback that uses it:

```manuscript
import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Result[Bytes, FileSystemError]:
    return fn():
        with file = try filesystem().open(path: path, flags: "r", mode: 0):
            return file.read_file(max_bytes: 1048576)
```

`notes_reader("notes.txt")` returns a callback; each call opens, reads, and closes its own file.

Capturing an already-open file keeps the same handle and does not delay its `with` cleanup: `FileHandle.read_file` after the block returns `FileSystemError.Closed`. Parameters and record fields follow the same lifetime rule.

## Contextual callback inference

```manuscript

fn names() List[String]:
    return [1, 2].map(fn(value): value.to_string())
```

The list supplies `Int` for `value`, and the expected `List[String]` supplies the callback result. Other arguments may establish callback inputs in any written order; callbacks are revisited as context appears, and runtime order is unchanged. An unambiguous expected result may establish generic arguments first ([inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type while the body gives the success type. Otherwise add a specialization or annotation.
