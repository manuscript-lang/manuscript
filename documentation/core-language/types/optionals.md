+++
title = "Optional values"
weight = 4
+++

# Optional values

Use `T?` when a value may be absent: an optional name, a failed lookup, or text that might not contain a number. It holds a `T` or `null`; a plain `T` becomes present wherever a `T?` is expected. `null` needs no import.

Save as `greeting.ms` and run `ms run greeting.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Ada!\nHello, guest!\n"} -->
```manuscript
fn greeting(name: String?) String:
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
explicit: String? := null
// Rejected: no type determines the absent payload.
unknown := null
// Wrapped: an annotated binding expects an Optional.
wrapped: String? := "Ada"
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
- Generic inference matches either the whole optional or its payload: `fn present[T](value: T?) T?` infers `T = Int` from `present(4)`. The payload type also gives context to an empty list or incomplete constructor.
- The same wrapping applies wherever a `T?` is expected: an annotated binding, an assignment, a return, a field or payload, a default, or a collection element (`id: Int? := 3`). A user-defined `Optional` gets no wrapping.

For omitted and labeled arguments, see [declarations and calls](../functions/declarations-and-calls.md#argument-names).

## Checking and extracting values

Receiver methods:

| Method | Behavior |
| --- | --- |
| `is_some() Bool` | Whether the optional contains a value, including `false`, zero, or an empty string |
| `is_none() Bool` | Whether the optional is absent |
| `get() T` | Return the contained value; on `null`, [fault](../errors/faults.md) with `called Optional.get() on null` |
| `get_or(default: T?) T` | Return the contained value, or `default` when absent |
| `map[U](transform: fn(move T) U) U?` | Consume the Optional and hand a present payload to `transform` once; preserve absence |
| `and_then[U](transform: fn(move T) U?) U?` | Consume the Optional and return the callback's Optional when present; preserve absence |
| `get_or_else(create: fn() T) T` | Return the contained value, or call `create` once when absent |
| `or_else(create: fn() T?) T?` | Consume the Optional: return it when present, or call `create` once when absent |

Fallback for routine absence:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn display_name(name: String?) String:
    return name or "Anonymous"
```

`get_or(default)` always evaluates its argument. Use `get_or_else` when the fallback costs work:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn display_name(create: fn() String, name: String?) String:
    return name or create()
```

Prefer `if v := x` to test and unwrap in one step, rather than `is_some()` followed by `get()`. `ms lint` reports a `get()` with no default as advisory **MSL110**, because it faults on `null`; use `get_or(default)` or unwrap with `if v := x` instead.

For a map lookup, write `m.get_or(key, fallback)` or `m[key]` (which faults when the key is absent) instead of `m.get(key) or fallback` or `m.get(key).get()`. `ms lint --fix` rewrites the first form.

Unwrapping with `if v := x`:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn greet(name: String?) String:
    if value := name:
        return "Hello, " + value
    return "Hello!"
```

Extraction returns the payload itself: no clone, no flattening. `map` transforms a payload; `and_then` chains an operation that returns an Optional:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn first_number(text: String?) Int?:
    return text.map(fn value: value.trim().clone()).and_then(fn value: value.parse_int())
```

`map` keeps nesting if its callback returns an Optional; `and_then` does not. Callbacks run in the caller's context; faults and cancellation propagate.

`map`, `and_then` and `or_else` take their receiver (`fn move`), so the callback owns the payload and the Optional is gone after the call. Write `x.clone().map(...)` to keep `x`.

An Optional read in place from a collection or another value (`xs.first()`, `m.get(key)`) is not the caller's to give away. Read it with `if v := xs.first():`, or `.clone()` it first.

A callback that only reads its argument is accepted where `fn(move T)` is expected; the call drops the payload when the callback returns.

[`if v := x`](../control-flow/conditionals.md#unwrapping-an-optional-or-result) binds the payload for a block, with optional `else`:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn display_name(name: String?) String:
    if value := name:
        return value.clone()
    return "Anonymous"
```

A [match](../control-flow/pattern-matching.md) on an Optional writes the present arm as a bare lowercase name beside `null:`; `v:` binds the payload. `ms lint` reports a two-arm match as MSL108.

Use [Result](../errors/results.md) when a failure needs an explanation.

## Unwrapping with `?`

Postfix `?` gives the present value, or leaves the function when the value is absent. It is the same operator as [error propagation](../errors/propagation.md): on a `Result` it returns the error, on an Optional it returns `null`. The enclosing function must return an Optional (`U?`) or `Void`; a `Void` function simply returns. Inside an anonymous function `?` returns from that function.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Address:
    city: String?

type User:
    address: Address?

fn city_length(user: User?) Int?:
    return user?.address?.city?.length()
```

`user?.address` is `(user?).address`. If `user` is `null`, the function returns `null` at that point; nothing after it on the line runs, so `a?.f(args)` evaluates `args` only when `a` is present. There is no separate chaining operator.

A function cannot mix the two kinds: `?` on a Result needs a Result return, and `?` on an Optional needs an Optional or `Void` return. Convert explicitly with `ok_or`, `if v := x:`, or `get_or(default)`.

`?` takes its access from the value it is applied to. It borrows the optional it starts from; when that place is a `var` (a `var` binding or parameter, or a field of one), a `var fn` called through it, or a change to the payload, lands in the optional itself, in place:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Counter:
    n: Int

fn var Counter.bump() Int:
    self.n += 1
    return self.n

fn tick(var counter: Counter?) Int?:
    return counter?.bump()
```

Through a `:=` binding or a parameter not declared `var`, `counter?.bump()` is rejected like any other change to that binding. `?` cannot move a field out of the optional it reads, so end the expression with `.clone()` to get an owned `String` or other field value.

## Converting absence to a Result

- `ok_or[E](cause: E) Result[T, E]`: `ok` with the payload, or `error` with `cause` when absent. `cause` is evaluated eagerly; `E` may be any value type.
- `ok_or_else[E](create: fn() E) Result[T, E]`: calls `create` once, only on absence.

Pass the error explicitly. Any function whose error type is `Error` can `?` the result:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn port_number(text: String) Int!:
    port := text.parse_int().ok_or(Error("missing port"))?
    return ok(port)
```

To keep the success value and discard the error, use [Result.to_optional](../errors/results.md#converting-success-to-an-optional).

## Data modeling

A [type](named-types.md) can have optional fields such as `email: String?`. Manuscript has no nullable references, so absence always appears in the declared type.
