+++
title = "Destructuring bindings"
weight = 8
+++

# Destructuring bindings

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Destructuring binds parts of a value to local names. `[...]` selects positions; `{...}` selects record fields. Each selected value keeps its static type.

## Positional bindings

```text
let [resA, resB] = try parallel(tasks: [first, second])
let [first_name, second_name] = names
```

The parallel fragment requires an enclosing `Result[U, ExecutionError]` function; Unit tests match the outer Result. See [explicit error adaptation](../../concurrency/parallel.md).

Positions bind from left to right. Fixed positional results preserve each position's individual type, as described by [parallel operations](../../concurrency/parallel.md). A fixed result's arity must match the pattern at compile time.

A `List[T]` can also be destructured; every bound position has type `T`. Its length must match the pattern. A mismatch is statically known only when the initializer is syntactically a list literal (ignoring grouping); a mismatch then is a compile error. Other list expressions are checked at runtime and mismatch faults, even when a previous binding happened to use a literal. Fixed packs always retain static arity. Destructuring does not silently discard extra elements or create values for missing positions.

Use brackets for positional patterns. `let (resA, resB) = value` is not a binding pattern.

## Record bindings

```text
let {name, email} = customer
let {name: customer_name, email: customer_email} = customer
```

Shorthand binds a field to a local with the same name. `field: local` renames the binding; the field name appears on the left. A pattern can select a subset of fields without creating a new record. Field names must exist on the statically known record type, and each local receives the selected field's type. A `Map` is not a record and does not support named-field patterns.

## Nested patterns

```text
let {customer: {name}, shipping: {city: destination}} = order
let [{name: first_name}, {name: second_name}] = customers
```

Patterns can nest whenever the source types support the selected positions or fields. The initializer is evaluated once. The compiler checks the whole pattern for field and shape compatibility, duplicate binding names, and shadowing before accepting the declaration. Extraction proceeds in written pattern order.

Both `let` and `var` accept binding patterns; they make all introduced locals immutable or reassignable respectively. Each local's type is inferred independently from its selected value. These patterns do not change the syntax of tagged alternative cases in `match`.

The accepted syntax here covers positional bindings, record shorthand, renaming, and nesting. Elisions, rest patterns, default initializers, destructuring assignment, and parameter patterns are rejected.

[Previous: Bindings and scope](bindings.md) · [Next: Numbers and booleans](numbers-and-booleans.md)
