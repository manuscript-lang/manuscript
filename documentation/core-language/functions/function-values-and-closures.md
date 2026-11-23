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

fn main() Int:
    offset := 1
    decrement := fn(value: Int) Int:
        return value - offset
    print(apply(3, decrement))
    return 0
```

```text
2
```

Function types name no parameters. A parameter the function changes in place is marked `var`: `fn(var List[Int]) Void` ([changing parameters](#changing-parameters)).

- Calls through any function value are positional, whether its type is written (`fn(Int) Int`) or inferred from a named function (`f := subtract_one`); a label on such a call is an error. Only a call that names the declaration, `subtract_one(amount: 1)`, takes labels. Suspension and evaluation order are the same as for declared functions.
- A named or anonymous `fn` inside a function is a local binding of a function value.
- Inferred immutable copies of a named function keep its [default arguments](declarations-and-calls.md#default-arguments), but only trailing ones can be omitted because a copy takes no labels to skip an earlier one; explicit function types require all parameters.

## Function type compatibility

Parameter types in order, their `var` and `move` markers, and the result type are function-type identity. Compatibility is invariant except for one adaptation: a function that only reads a parameter may stand in where one that changes it (`var`) is expected ([changing parameters](#changing-parameters)); `move` always matches exactly. Parameter names are not part of it: `fn f(amount: Int) Int` and `fn g(value: Int) Int` both fit `fn(Int) Int`. A mismatch needs an explicit adapter function.

<!-- manuscript-example: {"mode":"error","contains":"expected fn(Int) String","context":"fn apply(value: Int, transform: fn(Int) Int) Int:\n    return transform(value)","given":[]} -->
```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

fn adapt() Void:
    ok: fn(Int) Int := subtract_one
    // Rejected: the result type differs.
    invalid: fn(Int) String := subtract_one
    result := apply(value: 3, transform: ok)
```

An anonymous function may omit parameter types when context supplies them (argument, annotation, field, collection element, or return type). Parameters match by position: `increment: fn(Int) Int = fn item: item + 1` is called as `increment(3)`.

- An omitted result type comes from context or the body: returns must share one exact type, fallthrough adds `Void`, `Never` adds nothing.
- Without context, callbacks need parameter annotations.
- A generic function must be instantiated to be a value: `identity[Int]`, not bare `identity`.
- A method that takes its receiver (`fn move T.m`, or one whose body keeps `self`) cannot be used as a value: the value could be called again, and each call would need its own receiver. Write the copy in a closure (`fn: item.clone().listed()`), or call the method.
- A bound method value has the operation's function type with the receiver bound. It borrows the receiver while it stays local, as a closure capturing it would, and takes the receiver when it is stored, returned or passed to a moving parameter: `find := re.find_all` keeps `re` readable, `holders.append(re.find_all)` moves `re` at its last use.
- An anonymous function is its own boundary for `return`, `?`, `break`, and `continue`.

## Changing parameters

A function that changes its caller's variable declares the parameter `var`, and its function type says so: `fn push_one(var values: List[Int]) Void` has type `fn(var List[Int]) Void`. A call through the value passes the argument plainly, exactly as a direct call does (the type says it is changed), and the argument must be a variable or a field of one. An anonymous function declares a `var` parameter the same way.

`fn(List[Int]) Void` and `fn(var List[Int]) Void` are different types:

- A function that only reads a parameter may be used where one that may change it is expected. `apply(fn(xs: List[Int]): void, values)` is accepted, and the callee's `var` argument is passed to it as a plain read.
- The other direction is an error: a function that changes its parameter cannot stand in for one that only reads it.

A function that takes ownership of a parameter says so in its type: `fn keep(move item: Item) Int` has type `fn(move Item) Int`. A call through the value hands the argument over, so the caller's name is dead after it.

- **Anonymous functions** take `move` from the expected type, or declare it as `fn move item: ...`. They then own the argument and may keep it, even a resource. One that only reads it drops the argument (closing a resource) when it returns.
- **Reading is accepted where `move` is expected.** A function that only reads a parameter may stand in for `fn(move T)`: the call drops the argument when it returns.
- **Keeping is not accepted where borrowing is expected.** A named function that keeps a parameter, used where the function type borrows it (`fn(T)`), would need a hidden copy of every argument. Write the copy in a closure instead: `fn x: keep(x.clone())`.

See [moving into a function](../types/references.md#moving-into-a-function).

`List.for_each` and `Map.for_each` take a callback whose element (a map's value) is `var`, so the callback can change elements in place: `scores.for_each(fn var s: s = s + 1)`. A callback that changes the parameter makes `scores` a changed receiver, so it must be a `var` and the callback must not touch it; a callback that only reads works on a `:=` list.

The rule is general: any method whose callback type has a `var` position of one of the receiver's type arguments behaves this way. Such a method cannot be taken as a value from a variable (`each := scores.for_each`); call it, or write a closure.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn push_one(var values: List[Int]) Void:
    values.append(1)

fn apply(change: fn(var List[Int]) Void, var values: List[Int]) Void:
    change(values)

fn changed() List[Int]:
    var values: List[Int] = []
    apply(push_one, values)
    apply(fn(var xs: List[Int]): xs.append(2), values)
    return values
```

The value travels by address, so a value with one owner (a list, a type holding one) is changed where it lives and never copied. A function with both a `var` parameter and a parameter default cannot be a function value; call it from a closure that supplies the default.

A closure that outlives the call (returned, stored, or started as a `promise`) cannot capture a `var` parameter or a `var` receiver for the same reason: the caller still owns it and drops it when the call returns. Take the parameter by value and pass it to the closure at the call, or capture `.clone()`.

A `var` parameter is the caller's value, so the function cannot move it out (`old := values` is an error). The one exception is the right side of an assignment to the parameter itself, which refills it before the caller sees it: `values = rebuilt(values)`, or `exchange = Tap(inner: exchange, ...)` to replace an interface value with a wrapper that owns it. A [contract type match](../control-flow/pattern-matching.md#contract-type-patterns) recovers the wrapper afterwards.

## Closure captures

Captures follow ownership rules. A non-escaping closure borrows its captures; an escaping closure owns them. The checker infers escape and parameter modes.

A closure that only reads its captures and is called only in the function that made it borrows them, so the captured variable cannot change while the closure is still used. Make the changes first, then create the closure:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn tag_count() Int:
    var tags = ["docs"]
    tags.append("release")
    count := fn:
        return tags.length()
    return count()
// tag_count() returns 2.
```

A closure that is called only in the function that made it (including a callback such as `for_each`) may also change what it captures. It shares the captured variable, so the change lands in the original, and the variable cannot be used elsewhere while the closure is still used:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn total(values: List[Int]) Int:
    var sum = 0
    values.for_each(fn value:
        sum += value
    )
    return sum
```

A function value never changes, so the checker shares it freely: pass it, store it, or capture it in several closures and keep using the original. It has no `.clone()`, so a type or list that holds one is not `Clonable`.

A closure that is returned or stored owns what it captures, so it cannot change a captured variable:

- **Moving a variable in.** The closure takes a captured variable when the closure is its last use. If the variable is used again, or is only borrowed (a loop variable, or a `:=` that borrows another value), bind a `.clone()` before the closure and capture that.
- **Parameters.** A parameter the closure takes is moved by the function, so the caller gives the value up. Pass `.clone()` to keep it.
- **A `var` used again.** A returned or stored closure cannot capture a `var` that is used after the closure is made, because it would keep a stale copy. Bind a `:=` copy first (`base := offset`) and capture that.

A bound method keeps its receiver by the same rules. A method that changes its receiver (`add := xs.append`) shares the variable like a closure that changes it, so `xs` must be a `var`, cannot be used while `add` is still used, and `add` cannot be returned or stored. Taking such a method from a field (`bag.items.append`) is an error; call it, or write a closure. The parameter case, with the caller keeping its list:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Counter:
    read: fn() Int

fn counter(values: List[Int]) Counter:
    return Counter(read: fn: values.length())

fn total() Int:
    values := [1, 2]
    c := counter(values.clone())
    return c.read() + values.length()
```

## Resource captures

Open a resource inside the callback that uses it:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Bytes!:
    return fn:
        file := open(path: path)?
        return file.read_file(max_bytes: 1048576)
```

`notes_reader("notes.txt")` returns a callback; each call opens, reads, and closes its own file.

A non-escaping callback can borrow an already-open file while its owner stays in scope. An escaping closure must own its captures; moving a file into it transfers the cleanup duty. It cannot keep a borrow of a local file after that local scope ends. See [ownership and resource cleanup](../types/references.md#references-inside-other-values).

## Contextual callback inference

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn names() List[String]:
    return [1, 2].map(fn value: value.to_string())
```

The list supplies `Int` for `value`, and the expected `List[String]` supplies the callback result. Other arguments may establish callback inputs in any written order; callbacks are revisited as context appears, and runtime order is unchanged. An unambiguous expected result may establish generic arguments first ([inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type while the body gives the success type. Otherwise add a specialization or annotation.
