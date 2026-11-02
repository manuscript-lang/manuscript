+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

Store a function in a binding or pass it as an argument. Anonymous functions use `fn`; the type is `fn(T) U`. A closure borrows or owns the bindings it captures.

```manuscript
fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

let offset = 1
let decrement = fn(value: Int) Int:
    return value - offset

let result = apply(value: 3, transform: decrement)
```

Function types name no parameters. Calls through function values are positional (a label on such a call is an error) and share the suspension and evaluation of declared functions. A named or anonymous `fn` inside a function is a local binding of a function value. Inferred immutable copies keep [default arguments](declarations-and-calls.md#default-arguments); explicit function types require all parameters.

## Function type compatibility

Parameter types in order and the result type are function-type identity, and compatibility is invariant. Parameter names are not part of it: `fn f(amount: Int) Int` and `fn g(value: Int) Int` both fit `fn(Int) Int`. A mismatch needs an explicit adapter function.

```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

fn adapt() Unit:
    let ok: fn(Int) Int = subtract_one
    # Rejected: the result type differs.
    let invalid: fn(Int) String = subtract_one
    let result = apply(value: 3, transform: ok)
```

An anonymous function may omit parameter types when context supplies them (argument, annotation, field, collection element, or return type). Parameters match by position: `let increment: fn(Int) Int = fn item: item + 1` is called as `increment(3)`.

- An omitted result type comes from context or the body: returns must share one exact type, fallthrough adds `Unit`, `Never` adds nothing.
- Without context, callbacks need parameter annotations.
- A generic function must be instantiated to be a value: `identity[Int]`, not bare `identity`.
- A bound method value has the operation's function type with the receiver bound.
- An anonymous function is its own boundary for `return`, `try`, `break`, and `continue`.

<a id="snapshot-captures"></a>

## Closure captures

Captures follow ownership rules. A non-escaping closure borrows its captures; an escaping closure owns them. The checker infers escape and parameter modes.

A closure that is only called in the function that made it borrows what it captures, so the captured variable cannot change while the closure is still used. Make the changes first, then create the closure:

```manuscript

fn tag_count() Int:
    var tags = ["docs"]
    tags.append("release")
    let count = fn:
        return tags.length()
    return count()
# tag_count() returns 2.
```

A closure that only the function that made it calls (including a callback such as `for_each`) may change what it captures. It shares the captured variable, so the change lands in the original, and the variable cannot be used elsewhere while the closure is still used:

```manuscript
fn total(values: List[Int]) Int:
    var sum = 0
    values.for_each(fn value:
        sum += value
    )
    return sum
```

A closure that is returned or stored owns what it captures instead, so it cannot change a captured variable. It moves a captured variable in when the closure is its last use; when the variable is used again, or is only borrowed (a parameter, a loop variable), bind a `.clone()` before the closure and capture that. A bound method keeps its receiver by the same rules: a method that changes its receiver (`let add = xs.append`) shares the variable like a closure that changes it, so `xs` must be a `var`, cannot be used while `add` is still used, and `add` cannot be returned or stored. Taking such a method from a field (`bag.items.append`) is an error; call it or write a closure.

## Resource captures

Open a resource inside the callback that uses it:

```manuscript
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Bytes!:
    return fn:
        let file = try open(path: path, flags: "r", mode: 0)
        return file.read_file(max_bytes: 1048576)
```

`notes_reader("notes.txt")` returns a callback; each call opens, reads, and closes its own file.

Capturing an already-open file keeps the same handle and does not delay its scope-end cleanup: `FileHandle.read_file` after the scope ends returns an `Error` of kind `Closed`. Parameters and record fields follow the same lifetime rule.

## Contextual callback inference

```manuscript

fn names() List[String]:
    return [1, 2].map(fn value: value.to_string())
```

The list supplies `Int` for `value`, and the expected `List[String]` supplies the callback result. Other arguments may establish callback inputs in any written order; callbacks are revisited as context appears, and runtime order is unchanged. An unambiguous expected result may establish generic arguments first ([inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type while the body gives the success type. Otherwise add a specialization or annotation.
