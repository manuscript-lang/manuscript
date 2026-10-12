+++
title = "Function values and closures"
weight = 22
+++

# Function values and closures

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

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

Function types retain parameter names. Calls through values may omit the label when the function type has exactly one parameter; multi-parameter function types require labels on every supplied argument. Labels remain part of function-type identity and compatibility even when a call omits one. Calls have the same suspension and evaluation rules as declared functions.

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

The rejected binding is a negative example; removing it leaves a valid function. Anonymous functions require explicit parameter and result types and an indented body, exactly as specified in the [grammar](../basics/grammar.md). An annotation on the receiving variable does not omit those signatures. A generic function must be instantiated before it is stored as a value; `identity[Int]` is a function value, while a bare polymorphic `identity` is not. Bound method values have the operation's function type with the receiver already bound and excluded from the parameter list.

An anonymous function forms its own function boundary for `return`, `try`, `break`, and `continue`. Its control-flow exits cannot exit the containing function or loop. Capture and sharing behavior remains governed by the separate contracts below.

## Snapshot captures

A closure snapshots each referenced local binding when created, including a `var`'s current value. Later reassignment of that local does not change the snapshot. Assigning to a captured outer local is a compile error; shared mutable local cells are not implicit. Shared mutable state is accessed through synchronized services.

Immutable data is retained by value/reference as appropriate for its representation. A service or resource capture retains a reference to the same object, not a deep copy of the object's state. Bound methods retain their receiver under the same rules. Retained environments survive through garbage collection; there is no move, borrowed capture, or automatic cleanup on closure invocation/discard.

## Resource captures

```manuscript
with file = try files.open(path: "data.txt"):
    let reader = fn() -> Result[Optional[Bytes], IoError]:
        return file.read(max_bytes: 4096)
    callbacks.register(handler: reader)

# A later callback invocation reports IoError.Closed.
```

The acquisition fragment belongs to a function returning `Result[U, IoError]`; callbacks is an explicitly supplied registration service. The acquired File and callback are ordinary values.

Capturing a resource does not extend its open lifetime or cancel its `with` cleanup. Resource methods detect closed state at runtime. This applies equally to resources passed through explicit parameters or retained in records.

## Concurrent invocation

Concurrency APIs accept ordinary functions. Function parameters, returned functions, function fields, and generic forwarding work exactly as local function values do. See [function sharing](../../ownership-and-cleanup/values/sharing.md#function-values). A shared resource can still be closed before invocation.

Capture request-data snapshots and application services for background work, then acquire job resources within that operation. `parallel` joins before returning, so an enclosing `with` remains active while its operations run, unless the resource is explicitly closed elsewhere.

These examples use inferred captures. An explicit capture-list syntax has not been selected and is not required by this design. See [parallel](../../concurrency/parallel.md), [background services](../../standard-library/tasks/background.md), and [reference sharing](../../ownership-and-cleanup/values/sharing.md).

[Previous: Declarations and calls](declarations-and-calls.md) · [Next: Conditionals](../control-flow/conditionals.md)
