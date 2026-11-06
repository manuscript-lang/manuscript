+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

Store a function in a binding or pass it as an argument. Anonymous functions use `fn`; the type is `fn(T) U`. A closure borrows or owns the bindings it captures.

Save as `callback.ms` and run `ms run callback.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"2\n"} -->
```manuscript
fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

export fn main() Int:
    let offset = 1
    let decrement = fn(value: Int) Int:
        return value - offset
    print(apply(3, decrement))
    return 0
```

```text
2
```

Function types name no parameters; `fn(var List[Int]) Unit` marks one the function changes in place ([changing parameters](#changing-parameters)). Calls through function values are positional (a label on such a call is an error) and share the suspension and evaluation of declared functions. A named or anonymous `fn` inside a function is a local binding of a function value. Inferred immutable copies keep [default arguments](declarations-and-calls.md#default-arguments); explicit function types require all parameters.

## Function type compatibility

Parameter types in order, their `var` markers, and the result type are function-type identity, and compatibility is invariant. Parameter names are not part of it: `fn f(amount: Int) Int` and `fn g(value: Int) Int` both fit `fn(Int) Int`. A mismatch needs an explicit adapter function.

```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

fn adapt() Unit:
    let ok: fn(Int) Int = subtract_one
    // Rejected: the result type differs.
    let invalid: fn(Int) String = subtract_one
    let result = apply(value: 3, transform: ok)
```

An anonymous function may omit parameter types when context supplies them (argument, annotation, field, collection element, or return type). Parameters match by position: `let increment: fn(Int) Int = fn item: item + 1` is called as `increment(3)`.

- An omitted result type comes from context or the body: returns must share one exact type, fallthrough adds `Unit`, `Never` adds nothing.
- Without context, callbacks need parameter annotations.
- A generic function must be instantiated to be a value: `identity[Int]`, not bare `identity`.
- A bound method value has the operation's function type with the receiver bound. It borrows the receiver while it stays local, as a closure capturing it would, and takes the receiver when it is stored, returned or passed to a moving parameter: `let find = re.find_all` keeps `re` readable, `holders.append(re.find_all)` moves `re` at its last use.
- An anonymous function is its own boundary for `return`, `try`, `break`, and `continue`.

## Changing parameters

A function that changes its caller's variable declares the parameter `var`, and its function type says so: `fn push_one(var values: List[Int]) Unit` has type `fn(var List[Int]) Unit`. A call through the value marks the argument `var`, exactly as a direct call does, and the argument must be a variable or a field of one. An anonymous function declares a `var` parameter the same way. `fn(List[Int]) Unit` and `fn(var List[Int]) Unit` are different types, but a function that only reads a parameter may be used where one that may change it is expected: `apply(fn(xs: List[Int]): unit, var values)` is accepted, and the callee's `var` argument is passed to it as a plain read. The other direction is an error: a function that changes its parameter cannot stand in for one that only reads it.

```manuscript
fn push_one(var values: List[Int]) Unit:
    values.append(1)

fn apply(change: fn(var List[Int]) Unit, var values: List[Int]) Unit:
    change(var values)

fn changed() List[Int]:
    var values: List[Int] = []
    apply(push_one, var values)
    apply(fn(var xs: List[Int]): xs.append(2), var values)
    return values
```

The value travels by address, so a value with one owner (a list, a type holding one) is changed where it lives and never copied. A function with both a `var` parameter and a parameter default cannot be a function value; call it from a closure that supplies the default.

A `var` parameter is the caller's value, so the function cannot move it out (`let old = values` is an error). The one exception is the right side of an assignment to the parameter itself, which refills it before the caller sees it: `values = rebuilt(values)`, or `exchange = Tap(inner: exchange, ...)` to replace an interface value with a wrapper that owns it. A [contract type match](../control-flow/pattern-matching.md#contract-type-patterns) recovers the wrapper afterwards.

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
// tag_count() returns 2.
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

A function value has one owner and no `.clone()`, and a type or list that holds one is not `Clonable`: pass it where it is only read, move it at its last use, or make it again from a named `fn`. A closure that is returned or stored owns what it captures instead, so it cannot change a captured variable. It moves a captured variable in when the closure is its last use; when the variable is used again, or is only borrowed (a loop variable, a `let` that borrows another value), bind a `.clone()` before the closure and capture that. A parameter the closure takes is moved by the function, so the caller gives the value up; pass `.clone()` to keep it. A returned or stored closure cannot capture a `var` that is used again after the closure is made, because it would keep a stale copy; bind a `let` copy first (`let base = offset`) and capture that. A bound method keeps its receiver by the same rules: a method that changes its receiver (`let add = xs.append`) shares the variable like a closure that changes it, so `xs` must be a `var`, cannot be used while `add` is still used, and `add` cannot be returned or stored. Taking such a method from a field (`bag.items.append`) is an error; call it or write a closure. The parameter case, with the caller keeping its list:

```manuscript
type Counter:
    read: fn() Int

fn counter(values: List[Int]) Counter:
    return Counter(read: fn: values.length())

fn total() Int:
    let values = [1, 2]
    let c = counter(values.clone())
    return c.read() + values.length()
```

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

A non-escaping callback can borrow an already-open file while its owner stays in scope. An escaping closure must own its captures; moving a file into it transfers the cleanup duty. It cannot keep a borrow of a local file after that local scope ends. See [ownership and resource cleanup](../types/references.md#references-inside-other-values).

## Contextual callback inference

```manuscript

fn names() List[String]:
    return [1, 2].map(fn value: value.to_string())
```

The list supplies `Int` for `value`, and the expected `List[String]` supplies the callback result. Other arguments may establish callback inputs in any written order; callbacks are revisited as context appears, and runtime order is unchanged. An unambiguous expected result may establish generic arguments first ([inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type while the body gives the success type. Otherwise add a specialization or annotation.
