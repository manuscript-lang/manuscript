+++
title = "Optional values"
weight = 4
+++

# Optional values

`T?` makes absence part of the declared type: it holds a `T` or `none`. There is no `some`: a plain `T` converts wherever a `T?` is expected, and `some(...)` is rejected. `none` is in the prelude.

```manuscript
let present: String? = "Ada"
let missing: String? = none
```

`T?` is the only spelling; `Optional[T]` is rejected. It applies to the type before it, so a function type needs parentheses: `fn(Int) Int?` returns an optional, `(fn(Int) Int)?` is an optional function.

A parameter or record field of type `T?` with no default is `none` when omitted, so `= none` is never written; a plain `T` passed for it wraps without `some`.

`T?` is an invariant alternative. `none` takes its type from the expected type, so the type is written on the binding; a bare `let x = 1` is an `Int`, not an `Int?`.

```manuscript
let explicit: String? = none
# Rejected: no type determines the absent payload.
let unknown = none
# Wrapped: an annotated binding expects an Optional.
let wrapped: String? = "Ada"
```

There is no implicit unwrapping or flattening: `Int??` differs from `Int?`. `Result[T, E]` likewise needs both arguments determined, possibly from the expected type. See [compatibility and expected types](compatibility.md).

## Passing optional arguments

An argument for a standard `T?` parameter may be a plain `T`; it is wrapped as the present case. An argument already `T?` passes unchanged, including `none`.

```manuscript
import Queue from "@std/queue.ms"

fn main() Unit:
    var _bounded = Queue[Int](capacity: 4)
    var _unbounded = Queue[Int]()
```

- Applies to functions, methods, function values, constructor fields, and alternative payloads.
- Wraps exactly one layer: an `Int?` fits `Int??`, a bare `Int` does not.
- The expression evaluates once, in argument order. Zero, `false`, and empty values stay present.
- Generic inference matches either the whole optional or its payload: `fn present[T](value: T?) T?` infers `T = Int` from `present(4)`. The payload type also gives context to an empty list or incomplete constructor.
- A `T?` parameter or field with no default is `none` when omitted.
- The same wrapping applies wherever a `T?` is expected: an annotated binding, an assignment, a return, a field or payload, a default, or a collection element (`let id: Int? = 3`). A user-defined `Optional` gets no wrapping.

See [declarations and calls](../functions/declarations-and-calls.md#argument-names).

## Checking and extracting values

Receiver methods:

| Method | Behavior |
| --- | --- |
| `is_some() Bool` | Whether the optional contains a value, including `false`, zero, or an empty string |
| `is_none() Bool` | Whether the optional is absent |
| `get(default: T?) T` | Return the contained value, or `default` when absent; without a default, [fault](../errors/faults.md) with `called Optional.get() on none` |
| `map[U](transform: fn(T) U) U?` | Transform a present payload once; preserve absence |
| `and_then[U](transform: fn(T) U?) U?` | Return the callback's Optional when present; preserve absence |
| `get_or_else(create: fn() T) T` | Return the contained value, or call `create` once when absent |
| `or_else(create: fn() T?) T?` | Keep a present Optional or call `create` once when absent |

Fallback for routine absence:

```manuscript
fn display_name(name: String?) String:
    return name.get("Anonymous")
```

`get(default)` always evaluates its argument. Use `get_or_else` when the fallback costs work:

```manuscript
fn display_name(name: String?, create: fn() String) String:
    return name.get_or_else(create)
```

Prefer `if let` to test and unwrap in one step over `is_some()` then `get()`; `ms lint` reports a `get()` with no default as advisory **MSL110**, because it faults on `none`; pass a default or unwrap with `if let`. For a map lookup, write `m.get_or(key, fallback)` or `m[key]` (which faults when absent) instead of `m.get(key).get(fallback)` or `m.get(key).get()`:

```manuscript
fn greet(name: String?) String:
    if let value = name:
        return "Hello, " + value
    return "Hello!"
```

Extraction returns the payload itself: no clone, no flattening. `map` transforms a payload; `and_then` chains an operation that returns an Optional:

```manuscript
fn first_number(text: String?) Int?:
    return text.map(fn value: value.trim().clone()).and_then(fn value: value.parse_int())
```

`map` keeps nesting if its callback returns an Optional; `and_then` does not. Callbacks run in the caller's context; faults and cancellation propagate.

[`if let`](../control-flow/conditionals.md#unwrapping-an-optional-or-result) binds the payload for a block, with optional `else`:

```manuscript
fn display_name(name: String?) String:
    if let value = name:
        return value
    return "Anonymous"
```

A [match](../control-flow/pattern-matching.md) on an Optional writes the present arm as a bare lowercase name beside `none:`; `v:` binds the payload. A two-arm match is reported by `ms lint` as MSL108. Use [Result](../errors/results.md) when failure needs an explanation; `try` propagates only `Result` errors.

## Optional chaining

`a?.b` reads `b` when `a` is present and is `none` otherwise. The result is optional (`B?`), and stays `B?` rather than `B??` when `b` is already optional. The rest of the chain runs only when `a` is present, so `a?.f(args)` evaluates `args` only then, and `a?.b?.c` stops at the first `none`. Write `?.` with no space on either side; the receiver must be optional, since `.` already reads a member of a value that is always present.

```manuscript
type Address:
    city: String?

type User:
    address: Address?

fn city_length(user: User?) Int?:
    return user?.address?.city?.length()
```

A chain cannot move a field out of the optional it reads, so end an owned `String` or record field with `.clone()`.

A chain borrows the optional it starts from. When that place is a `var` (a `var` binding or parameter, or a field of one), the chain may call a `var fn` or change the payload, and the change lands in the optional itself, in place; on `none` nothing runs:

```manuscript
type Counter:
    n: Int

impl Counter:
    var fn bump() Int:
        self.n += 1
        return self.n

fn tick(var counter: Counter?) Int?:
    return counter?.bump()
```

Through a `let` or an undeclared-`var` parameter, `counter?.bump()` is rejected like any other change to that binding.

## Converting absence to a Result

- `ok_or[E: Error = MissingValue](cause: E?) Result[T, E]`: `ok` with the payload, or `error` with `cause` when absent. `cause` is evaluated eagerly; `E` must implement `Error`.
- `ok_or_else[E: Error](create: fn() E) Result[T, E]`: calls `create` once, only on absence.

Omitting the cause yields the prelude `MissingValue` (from `@std/core.ms`), the [default type argument](generics.md#default-type-arguments). It records the source file and line of the `ok_or()` call, and `message()` reports them, such as `missing value at src/main.ms:12`. Since `MissingValue` implements `Error`, `try` flattens it in any function whose error type is `Error`:

```manuscript
fn port_number(text: String) Result[Int, Error]:
    let port = try text.parse_int().ok_or()
    return ok(port)
```

A context fixing another error type, such as `Result[Int, TextError]`, needs a cause; omitting it faults with `called Optional.ok_or() without a cause for an error type other than MissingValue`.

[Result.to_optional](../errors/results.md#converting-success-to-an-optional) to keep success while discarding an error.

## Data modeling

A [record](records.md) can have optional fields such as `email: String?`. Manuscript has no nullable references; absence always lives in the declared type.
