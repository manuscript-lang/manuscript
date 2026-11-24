+++
title = "Optional values"
weight = 4
+++

# Optional values

Use `T?` when a value may be absent: an optional name, a failed lookup, or text that might not contain a number. It holds a `T` or `null`; a plain `T` becomes present wherever a `T?` is expected. `null` needs no import.

Save as `greeting.ms` and run `ms run greeting.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Ada!\nHello, guest!\n"} -->
```manuscript
fn greeting(name String?) String:
    return f"Hello, {name or "guest"}!"

fn main() Void:
    print(greeting("Ada"))
    print(greeting())
```

```text
Hello, Ada!
Hello, guest!
```

`get_or("guest")` supplies a fallback only when the value is absent. An empty string is still present. There is no `some(...)` constructor.

`T?` is the only spelling; `Optional[T]` is rejected. It applies to the type before it, so a function type needs parentheses: `fn(Int) Int?` returns an optional, `(fn(Int) Int)?` is an optional function.

A parameter or field of type `T?` with no default is `null` when omitted, so `= null` is never written; a plain `T` passed for it wraps without `some`.

`T?` is an invariant enum. `null` takes its type from the expected type, so the type is written on the binding; a bare `x := 1` is an `Int`, not an `Int?`.

<!-- manuscript-example: {"mode":"error","contains":"cannot infer the type of null","given":[]} -->
```manuscript
explicit String? := null
// Rejected: no type determines the absent payload.
unknown := null
// Wrapped: an annotated binding expects an Optional.
wrapped String? := "Ada"
```

There is no implicit unwrapping or flattening: `Int??` differs from `Int?`. `Result[T, E]` likewise needs both arguments determined, possibly from the expected type. See [compatibility and expected types](compatibility.md).

## Passing optional arguments

An argument for a standard `T?` parameter may be a plain `T`; it is wrapped as the present case. An argument already `T?` passes unchanged, including `null`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Queue from "@std/collections/queue.ms"

fn main() Void:
    var _bounded = Queue[Int](capacity: 4)
    var _unbounded = Queue[Int]()
```

- Applies to functions, methods, function values, constructor fields, and enum payloads.
- Wraps exactly one layer: an `Int?` fits `Int??`, a bare `Int` does not.
- The expression evaluates once, in argument order. Zero, `false`, and empty values stay present.
- Generic inference matches either the whole optional or its payload: `fn present[T](value T?) T?` infers `T = Int` from `present(4)`. The payload type also gives context to an empty list or incomplete constructor.
- The same wrapping applies wherever a `T?` is expected: an annotated binding, an assignment, a return, a field or payload, a default, or a collection element (`id Int? := 3`). A user-defined `Optional` gets no wrapping.

For omitted and labeled arguments, see [declarations and calls](../functions/declarations-and-calls.md#argument-names).

## Checking and extracting values

A `T?` has no methods. Compare it with `null`, give a fallback with `or`, and read the payload where the compiler can see it is present:

| Written | Meaning |
| --- | --- |
| `x == null`, `x != null` | Whether the optional is absent or present, including a present `false`, zero, or empty string |
| `x or d` | The payload, or `d` when absent; `d` is evaluated only when `x` is absent. With a `T` on the right the result is `T`; with a `T?` on the right it is `T?` |
| `ok_or(x, cause)` | `Ok(payload)`, or `Error(cause)` when absent |
| `x?` | The payload, or leave the function with `null` (see below) |

Fallback for routine absence:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn display_name(name String?) String:
    return name or "Anonymous"
```

The right side of `or` is evaluated only when the left is `null`, so a fallback that costs work is written directly:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn display_name(create fn() String, name String?) String:
    return name or create()
```

For a map lookup, write `m.get_or(key, fallback)` or `m[key]` (which faults when the key is absent) instead of `m.get(key) or fallback`. `ms lint --fix` rewrites the first form.

After `if v != null`, an immutable binding or parameter `v` reads as its payload type inside the block. A `v == null` test that exits (`return`, `break`, `continue`) leaves `v` present for the rest of the block, and `and`/`or` operands and `while` conditions narrow the same way. A `var` binding is not narrowed, because it can change; copy it into an immutable one first.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn greet(name String?) String:
    if name != null:
        return "Hello, " + name
    return "Hello!"
```

To test a value that is produced by a call, bind it first:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn first_number(text String?) Int?:
    if text == null: return null
    return text.trim().parse_int()
```

An Optional read in place from a collection or another value (`xs.first()`, `m.get(key)`) is not the caller's to give away. Bind it with `v := xs.first()` and test `v != null`, or `.clone()` it first.

A [match](../control-flow/pattern-matching.md) on an Optional writes the present arm as a bare lowercase name beside `null:`; `v:` binds the payload. `ms lint` reports a two-arm match as MSL108.

Use [Result](../errors/results.md) when a failure needs an explanation.

## Unwrapping with `?`

Postfix `?` gives the present value, or leaves the function when the value is absent. It is the same operator as [error propagation](../errors/propagation.md): on a `Result` it returns the error, on an Optional it returns `null`. The enclosing function must return an Optional (`U?`) or `Void`; a `Void` function simply returns. Inside an anonymous function `?` returns from that function.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Address:
    city String?

type User:
    address Address?

fn city_length(user User?) Int?:
    return user?.address?.city?.length()
```

`user?.address` is `(user?).address`. If `user` is `null`, the function returns `null` at that point; nothing after it on the line runs, so `a?.f(args)` evaluates `args` only when `a` is present. There is no separate chaining operator.

A function cannot mix the two kinds: `?` on a Result needs a Result return, and `?` on an Optional needs an Optional or `Void` return. Convert explicitly with `ok_or(x, cause)`, an `if x != null:` test, or `x or default`.

`?` takes its access from the value it is applied to. It borrows the optional it starts from; when that place is a `var` (a `var` binding or parameter, or a field of one), a `var fn` called through it, or a change to the payload, lands in the optional itself, in place:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Counter:
    n Int

fn var Counter.bump() Int:
    self.n += 1
    return self.n

fn tick(var counter Counter?) Int?:
    return counter?.bump()
```

Through a `:=` binding or a parameter not declared `var`, `counter?.bump()` is rejected like any other change to that binding. `?` cannot move a field out of the optional it reads, so end the expression with `.clone()` to get an owned `String` or other field value.

## Converting absence to a Result

- `ok_or[E](cause E) Result[T, E]`: `ok` with the payload, or `error` with `cause` when absent. `cause` is evaluated eagerly; `E` may be any value type.
- `ok_or_else[E](create fn() E) Result[T, E]`: calls `create` once, only on absence.

Pass the error explicitly. Any function whose error type is `Error` can `?` the result:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn port_number(text String) Int!:
    port := ok_or(text.parse_int(), Error("missing port"))?
    return ok(port)
```

To keep the success value and discard the error, use [Result.to_optional](../errors/results.md#converting-success-to-an-optional).

## Data modeling

A [type](named-types.md) can have optional fields such as `email String?`. Manuscript has no nullable references, so absence always appears in the declared type.
