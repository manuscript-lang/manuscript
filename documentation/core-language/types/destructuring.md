+++
title = "Destructuring bindings"
weight = 6
+++

# Destructuring bindings

Destructuring names parts of a value in one declaration: `[...]` for positions, `{...}` for record fields. Each name takes the type of the part it selects.

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

## Record bindings

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada: ada@example.com\nAda: ada@example.com\n"} -->
```manuscript
type Customer:
    name: String
    email: String

export fn main() Int:
    let customer = Customer("Ada", "ada@example.com")
    let {name, email} = customer
    print("{name}: {email}")
    let {name: customer_name, email: customer_email} = customer
    print("{customer_name}: {customer_email}")
    return 0
```

```text
Ada: ada@example.com
Ada: ada@example.com
```

Shorthand binds a field to a same-named local; `field: local` renames it. A pattern may select a subset of fields, which must exist on the statically known record type. A `Map` is not a record and takes no field patterns.

## Nested patterns

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada: London\nAda, Lin\n"} -->
```manuscript
type Customer:
    name: String

type Address:
    city: String

type Order:
    customer: Customer
    shipping: Address

export fn main() Int:
    let order = Order(Customer("Ada"), Address("London"))
    let customers = [Customer("Ada"), Customer("Lin")]
    let {customer: {name}, shipping: {city: destination}} = order
    let [{name: first_name}, {name: second_name}] = customers
    print("{name}: {destination}")
    print("{first_name}, {second_name}")
    return 0
```

```text
Ada: London
Ada, Lin
```

Patterns nest freely. The initializer is evaluated once and extraction follows pattern order. Duplicate binding names are rejected.

`let` makes every introduced local immutable and `var` makes them reassignable. Elisions, rest patterns, defaults, destructuring assignment, and parameter patterns are rejected.
