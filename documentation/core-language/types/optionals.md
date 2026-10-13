+++
title = "Optional values"
weight = 4
+++

# Optional values

Use `Optional[T]` when a value may be missing. `some(value: ...)` contains a value of type `T`; `none` means there is no value. `Optional`, `some`, and `none` are available from the prelude without imports.

```manuscript
let present: Optional[String] = some("Ada")
let missing: Optional[String] = none
```

Missing values use `Optional`. An optional makes absence part of the function's or field's declared type.

`Optional[T]` is an invariant alternative. Qualified cases are `Optional[T].some(value: ...)` and `Optional[T].none`. Unqualified forms use an expected optional type, or infer `T` from a `some` payload. `none` carries no evidence for `T` and needs context or explicit qualification.

```manuscript
let inferred = some(1)  # Optional[Int]
let explicit = Optional[String].none
# Rejected: no type determines the absent payload.
let unknown = none
# Rejected: bindings still require explicit wrapping.
let wrong: Optional[String] = "Ada"
```

There is no implicit unwrapping or flattening: `Optional[Optional[Int]]` differs from `Optional[Int]`. `Result[T, E]` likewise needs both arguments determined; an expected result type can supply the missing argument in `ok(value: ...)` or `error(cause: ...)`. See [compatibility and expected types](compatibility.md).

## Passing optional arguments

A supplied argument for a standard `Optional[T]` parameter may be a `T`. The compiler wraps it as `some(value: ...)` before the call. An argument already typed as `Optional[T]` passes through unchanged, including `none`.

```manuscript
import Queue from "@std/queues.ms"

let bounded = Queue[Int](capacity: 4)
let unbounded = Queue[Int]()
```

This rule applies to functions, methods, function values, constructor fields, and alternative payloads. It wraps exactly one layer: an `Optional[Int]` can be passed to an `Optional[Optional[Int]]` parameter as its payload, but a bare `Int` cannot. The expression evaluates once in written argument order, and the payload retains its identity. Zero, `false`, and empty values remain present.

Generic argument inference can match either the complete optional or its payload. For example, `fn present[T](value: Optional[T]) -> Optional[T]` infers `T = Int` from `present(4)` or from passing an existing `Optional[Int]`. Once a parameter type is known, its payload provides context for an empty list or an incomplete data constructor.

Omission still requires a default or a declared library omission permission. An `Optional[T]` parameter alone remains required. Bindings, assignments, returns, defaults, and collection elements continue to require explicit wrapping; numeric conversion, implicit unwrapping, and recursive wrapping are rejected. A user-defined alternative named `Optional` does not receive this rule. See [declarations and calls](../functions/declarations-and-calls.md#argument-names).

## Checking and extracting values

Optional has receiver methods for presence checks and extraction:

| Method | Behavior |
| --- | --- |
| `is_some() -> Bool` | Whether the optional contains a value, including `false`, zero, or an empty string |
| `is_none() -> Bool` | Whether the optional is absent |
| `unwrap() -> T` | Return the contained value; [fault](../errors/faults.md) with `called Optional.unwrap() on none` when absent |
| `unwrap_or(fallback: T) -> T` | Return the contained value or the supplied fallback |
| `unwrap_or_else(create: fn() -> T) -> T` | Return the contained value or call `create` once when absent |

Use a fallback for routine absence:

```manuscript
fn display_name(name: Optional[String]) -> String:
    return name.unwrap_or("Anonymous")
```

`unwrap_or` evaluates its argument even when the optional contains a value, following ordinary call evaluation. Use `unwrap_or_else` when the fallback requires work:

```manuscript
fn display_name(name: Optional[String], create: fn() -> String) -> String:
    return name.unwrap_or_else(create)
```

Use `unwrap` when presence is established or absence is a programming error:

```manuscript
fn greet(name: Optional[String]) -> String:
    if name.is_some():
        return "Hello, " + name.unwrap()
    return "Hello!"
```

Extraction returns the payload with its exact type and identity. It does not clone a record or collection, or flatten a nested optional. A fallback must have the same `T`; the lazy callback takes no arguments and returns `T`. A fault or cancellation in the callback propagates normally.

[Pattern matching](../control-flow/pattern-matching.md) remains available when distinct branches make the logic clearer:

```manuscript
fn display_name(name: Optional[String]) -> String:
    match name:
        some(value): return value
        none: return "Anonymous"
```

Use [Result](../errors/results.md) when a failure needs an explanation. An absent value and a failed operation express different contracts. `try` propagates a `Result` error; the design specifies no corresponding implicit propagation for an optional.

## Data modeling

A [record](records.md) can contain optional fields, such as `email: Optional[String]`. Manuscript has no nullable reference type: put absence in the declared type and handle it with Optional methods or [pattern matching](../control-flow/pattern-matching.md).
