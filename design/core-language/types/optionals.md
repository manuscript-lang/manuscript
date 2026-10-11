+++
title = "Optional values"
weight = 14
+++

# Optional values

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Import `Optional` from `@std/optional.ms`. `Optional[T]` describes either a value of type `T` or its absence. Its alternatives are `some(value: value)` and `none`.

```text
let present: Optional[String] = some(value: "Ada")
let missing: Optional[String] = none
```

Missing values use `Optional`. An optional makes absence part of the function's or field's declared type.

`Optional[T]` is an invariant alternative. Qualified cases are `Optional[T].some(value: ...)` and `Optional[T].none`. Unqualified forms use an expected optional type, or infer `T` from a `some` payload. `none` carries no evidence for `T` and needs context or explicit qualification.

```text
let inferred = some(value: 1)  # Optional[Int]
let explicit = Optional[String].none
# Rejected: no type determines the absent payload.
let unknown = none
# Rejected: no automatic wrapping.
let wrong: Optional[String] = "Ada"
```

There is no implicit unwrapping or flattening: `Optional[Optional[Int]]` differs from `Optional[Int]`. `Result[T, E]` likewise needs both arguments determined; an expected result type can supply the missing argument in `ok(value: ...)` or `error(cause: ...)`. See [compatibility and expected types](compatibility.md).

## Handling absence

```text
fn display_name(name: Optional[String]) -> String:
    match name:
        some(value):
            return value
        none:
            return "Anonymous"
```

The `some` branch binds the contained text. The `none` branch chooses what this application should do when no name is supplied. Both branches return `String`.

Use [Result](../errors/results.md) when a failure needs an explanation. An absent value and a failed operation express different contracts. `try` propagates a `Result` error; the design specifies no corresponding implicit propagation for an optional.

## Data modeling

A [record](records.md) can contain optional fields, such as `email: Optional[String]`. Manuscript has no nullable reference type: put absence in the declared type and handle it through ordinary [pattern matching](../control-flow/pattern-matching.md).

[Previous: Alternatives](alternatives.md) · [Next: Collections](collections.md)
