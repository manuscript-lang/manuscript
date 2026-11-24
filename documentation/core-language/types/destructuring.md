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
fn main() Void:
    names := ["Ada", "Grace"]
    [first_name, second_name] := names
    print(f"{first_name} and {second_name}")
```

```text
Ada and Grace
```

Positions bind left to right. A `List[T]` binds each position as `T`, and its length must match the pattern exactly. A length mismatch is a compile error when the initializer is a list literal and a runtime fault otherwise. Parenthesized patterns such as `(a, b) := value` are not binding patterns.

## Type bindings

<!-- manuscript-example: {"mode":"fragment","context":"type Customer:\n    name String\n    email String","given":["customer Customer"]} -->
```manuscript
{name, email} := customer
{name: customer_name, email: customer_email} := customer
```

Shorthand binds a field to a local of the same name; `field: local` renames it. A pattern may select a subset of fields, and each must exist on the statically known type. A `Map` has no named fields and takes no field patterns.

## Nested patterns

<!-- manuscript-example: {"mode":"fragment","context":"type Customer:\n    name String\n\ntype Address:\n    city String\n\ntype Order:\n    customer Customer\n    shipping Address","given":["order Order","customers List[Customer]"]} -->
```manuscript
{customer: {name}, shipping: {city: destination}} := order
[{name: first_name}, {name: second_name}] := customers
```

Patterns nest freely. The initializer is evaluated once, and extraction follows pattern order. Duplicate binding names are rejected.

`:=` makes every introduced local immutable, and `var` makes them reassignable. Skipping positions, rest patterns, default values, destructuring assignment, and parameter patterns are all rejected.
