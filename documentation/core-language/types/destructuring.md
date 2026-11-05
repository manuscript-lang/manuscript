+++
title = "Destructuring bindings"
weight = 6
+++

# Destructuring bindings

Destructuring names parts of a value in one declaration: `[...]` for positions, `{...}` for fields. Each name takes the type of the part it selects.

## Positional bindings

Save as `names.ms` and run `ms run names.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada and Grace\n"} -->
```manuscript
export fn main() Int:
    let names = ["Ada", "Grace"]
    let [first_name, second_name] = names
    print("{first_name} and {second_name}")
    return 0
```

```text
Ada and Grace
```

Positions bind left to right. A `List[T]` binds each position as `T`, and its length must match the pattern exactly. A mismatch is a compile error when the initializer is a list literal, and a runtime fault otherwise. Parenthesized patterns such as `let (a, b) = value` are not binding patterns.

## Type bindings

```manuscript
let {name, email} = customer
let {name: customer_name, email: customer_email} = customer
```

Shorthand binds a field to a same-named local; `field: local` renames it. A pattern may select a subset of fields, which must exist on the statically known type. A `Map` has no named fields and takes no field patterns.

## Nested patterns

```manuscript
let {customer: {name}, shipping: {city: destination}} = order
let [{name: first_name}, {name: second_name}] = customers
```

Patterns nest freely. The initializer is evaluated once and extraction follows pattern order. Duplicate binding names are rejected.

`let` makes every introduced local immutable and `var` makes them reassignable. Elisions, rest patterns, defaults, destructuring assignment, and parameter patterns are rejected.
