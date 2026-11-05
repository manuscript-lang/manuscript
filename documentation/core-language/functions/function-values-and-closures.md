+++
title = "Function values and closures"
weight = 2
+++

# Function values and closures

Store a function in a binding or pass it as an argument. Anonymous functions use `fn`; the type is `fn(T) U`. A closure borrows or owns the bindings it captures.

Save as `callback.ms` and run `ms run callback.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"2\n","filename":"callback.ms"} -->
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

Save as `adapter.ms` and run `ms run adapter.ms`. The first value preserves the
function's type; the second uses an explicit conversion to adapt its result:

<!-- manuscript-example: {"mode":"run","stdout":"2\n2\n","filename":"adapter.ms"} -->
```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

export fn main() Int:
    let numeric: fn(Int) Int = subtract_one
    let textual: fn(Int) String = fn value: subtract_one(value).to_string()
    print(numeric(3))
    print(textual(3))
    return 0
```

```text
2
2
```

Negative reference: save this independently as `invalid.ms` and run
`ms check invalid.ms`. It exits nonzero because the assigned function returns
`Int`, while the annotation requires `String`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["expected fn(Int) String, found fn(Int) Int"],"filename":"invalid.ms"} -->
```manuscript
fn subtract_one(amount: Int) Int:
    return amount - 1

export fn main() Int:
    let invalid: fn(Int) String = subtract_one
    print(invalid(3))
    return 0
```

An anonymous function may omit parameter types when context supplies them (argument, annotation, field, collection element, or return type). Parameters match by position: `let increment: fn(Int) Int = fn item: item + 1` is called as `increment(3)`.

- An omitted result type comes from context or the body: returns must share one exact type, fallthrough adds `Unit`, `Never` adds nothing.
- Without context, callbacks need parameter annotations.
- A generic function must be instantiated to be a value: `identity[Int]`, not bare `identity`.
- A bound method value has the operation's function type with the receiver bound. It borrows the receiver while it stays local, as a closure capturing it would, and takes the receiver when it is stored, returned or passed to a moving parameter: `let find = re.find_all` keeps `re` readable, `holders.append(re.find_all)` moves `re` at its last use.
- An anonymous function is its own boundary for `return`, `try`, `break`, and `continue`.

## Changing parameters

A function that changes its caller's variable declares the parameter `var`, and its function type says so: `fn push_one(var values: List[Int]) Unit` has type `fn(var List[Int]) Unit`. A call through the value marks the argument `var`, exactly as a direct call does, and the argument must be a variable or a field of one. An anonymous function declares a `var` parameter the same way. `fn(List[Int]) Unit` and `fn(var List[Int]) Unit` are different types.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[1, 2]\n"} -->
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

export fn main() Int:
    print(changed())
    return 0
```

```text
[1, 2]
```

The value travels by address, so a value with one owner (a list, a record holding one) is changed where it lives and never copied. A function with both a `var` parameter and a parameter default cannot be a function value; call it from a closure that supplies the default.

A `var` parameter still belongs to the caller. A local `let old = values` is a
read-only reborrow, not a move or a snapshot. Read through that borrow before
changing the original; once the borrow's last use has passed, mutation can resume.
Save as `reborrow.ms` and run `ms run reborrow.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Before: 2\n[1, 2, 3]\n","filename":"reborrow.ms"} -->
```manuscript
fn append_after_reading(var values: List[Int]) Unit:
    let old = values
    print("Before: {old.length()}")
    values.append(3)

export fn main() Int:
    var values = [1, 2]
    append_after_reading(var values)
    print(values)
    return 0
```

```text
Before: 2
[1, 2, 3]
```

An owning destination is different. A record field must own the value stored in
it, so this negative example tries to take the caller's list. Save as `invalid.ms`
and run `ms check invalid.ms`; the checker reports that the caller keeps ownership
of a `var` parameter:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["cannot move `values` out of the function: the caller keeps ownership of a var parameter"],"filename":"invalid.ms"} -->
```manuscript
type Snapshot:
    values: List[Int]

fn steal(var values: List[Int]) Snapshot:
    return Snapshot(values)

export fn main() Int:
    var values = [1, 2]
    let snapshot = steal(var values)
    print(snapshot.values)
    return 0
```

Use `Snapshot(values.clone())` when the record needs an independent list. The
exception to moving out of a `var` parameter is the right side of an assignment
to that parameter itself: the assignment refills it before the caller sees it.
For example, `values = rebuilt(values)` replaces the list, and
`exchange = Tap(inner: exchange, ...)` can replace an interface value with an
owning wrapper. A [contract type match](../control-flow/pattern-matching.md#contract-type-patterns)
recovers the wrapper afterwards.

## Closure captures

Captures follow ownership rules. A non-escaping closure borrows its captures; an escaping closure owns them. The checker infers escape and parameter modes.

### Local callbacks read captures

A closure that is only called in the function that made it borrows what it captures, so the captured variable cannot change while the closure is still used. Make the changes first, then create the closure:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"2\n"} -->
```manuscript
fn tag_count() Int:
    var tags = ["docs"]
    tags.append("release")
    let count = fn:
        return tags.length()
    return count()
// tag_count() returns 2.

export fn main() Int:
    print(tag_count())
    return 0
```

```text
2
```

### Local callbacks change captures

A closure that only the function that made it calls (including a callback such as `for_each`) may change what it captures. It shares the captured variable, so the change lands in the original, and the variable cannot be used elsewhere while the closure is still used:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"6\n"} -->
```manuscript
fn total(values: List[Int]) Int:
    var sum = 0
    values.for_each(fn value:
        sum += value
    )
    return sum

export fn main() Int:
    print(total([1, 2, 3]))
    return 0
```

```text
6
```

### Returned callbacks own captures

A callback that is returned or stored can outlive the function that created it.
It owns its captures instead of borrowing the creator's locals, and cannot change
a captured variable. A captured value moves in at its last use. If the source is
still needed, or is only borrowed (for example a loop variable), create an owned
`.clone()` before creating the callback and capture that copy.

A parameter captured by an owning closure is moved by the function. In the next
example, `counter` stores a callback in a record. The caller passes a clone so it
can still use its original list after constructing the counter:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"4\n"} -->
```manuscript
type Counter:
    read: fn() Int

fn counter(values: List[Int]) Counter:
    return Counter(read: fn: values.length())

fn total() Int:
    let values = [1, 2]
    let c = counter(values.clone())
    return c.read() + values.length()

export fn main() Int:
    print(total())
    return 0
```

```text
4
```

The stored callback reads the two-element copy, and the caller reads the original,
so their lengths add to `4`. The clone makes that independence explicit.

A returned or stored closure cannot capture a `var` that is used again after the
closure is made: it would keep a stale copy. Bind a `let` copy first and capture
that. For a scalar this can be `let base = offset`; for independently owned data,
use `.clone()`. A function value itself has one owner and no `.clone()`, and a
record or list holding one is not `Clonable`. Read it through a borrow, move it at
its last use, or create another function value from a named `fn`.

### Bound methods follow the receiver

Taking a method as a value also captures its receiver. A method that changes its
receiver, such as `let add = xs.append`, shares that variable like a mutating local
closure. `xs` must be a `var`, cannot be used elsewhere while `add` is still used,
and `add` cannot be returned or stored. Taking a mutating method from a field,
such as `bag.items.append`, is rejected; call it directly or write a closure.

## Resource captures

Open a resource inside the callback that uses it:

Save this complete example as `example.ms` and run `ms run example.ms` after creating `notes.txt` with the text `Notes`:

<!-- manuscript-example: {"mode":"run","stdout":"5\n","files":{"notes.txt":"Notes"},"cases":[{"exit_code":1,"stdout":"filesystem: file or directory not found: notes.txt\n"}]} -->
```manuscript
import open from "@std/os/fs.ms"
import Bytes from "@std/bytes.ms"

fn notes_reader(path: String) fn() Bytes!:
    return fn:
        let file = try open(path: path, flags: "r", mode: 0)
        return file.read_file(max_bytes: 1048576)

export fn main() Int:
    let read = notes_reader("notes.txt")
    let outcome = read().map_error(fn cause: print(cause.message))
    if let bytes = outcome:
        print(bytes.length())
        return 0
    return 1

```

```text
5
```

`notes_reader("notes.txt")` returns a callback; each call opens, reads, and closes its own file.

A non-escaping callback can borrow an already-open file while its owner stays in scope. An escaping closure must own its captures; moving a file into it transfers the cleanup duty. It cannot keep a borrow of a local file after that local scope ends. See [ownership and resource cleanup](../types/references.md#references-inside-other-values).

## Contextual callback inference

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[1, 2]\n"} -->
```manuscript
fn names() List[String]:
    return [1, 2].map(fn value: value.to_string())

export fn main() Int:
    print(names())
    return 0
```

```text
[1, 2]
```

The list supplies `Int` for `value`, and the expected `List[String]` supplies the callback result. Other arguments may establish callback inputs in any written order; callbacks are revisited as context appears, and runtime order is unchanged. An unambiguous expected result may establish generic arguments first ([inference](../types/generics.md#inference-from-arguments)). A Result context supplies the error type while the body gives the success type. Otherwise add a specialization or annotation.
