+++
title = "Variables and scope"
weight = 2
+++

# Variables and scope

`let` bindings cannot be reassigned; `var` bindings can.

Save as `stock.ms` and run `ms run stock.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"2 of 3 left\n"} -->
```manuscript
export fn main() Int:
    let count = 3
    var remaining = count
    remaining -= 1
    print("{remaining} of {count} left")
    return 0
```

```text
2 of 3 left
```

## Grouping bindings

`let (` and `var (` declare several bindings of one kind, one per line, indented four spaces, with the closing `)` aligned with the keyword. Each entry is the same as a single binding, including an optional annotation or a destructuring pattern, and later entries see earlier ones.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada: true; 0 of 3 attempts\n"} -->
```manuscript
export fn main() Int:
    let (
        name = "Ada"
        active: Bool = true
    )
    var (
        attempts = 0
        limit = attempts + 3
    )
    print("{name}: {active}; {attempts} of {limit} attempts")
    return 0
```

```text
Ada: true; 0 of 3 attempts
```

A group is only a layout: entries are separate bindings with their own scope rules, and the formatter keeps the group together. Separate entries by lines, not commas, and use `let [a, b] = pair` to destructure. A group cannot sit in an inline body such as `if ready: let (`.

## Local type inference

Parameters and return types are explicit; local annotations are optional. `let count = 3` and `let count: Int = 3` are the same. Constructors also infer types. This continues the `Customer` and `welcome` declarations in [source files](syntax.md):

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Welcome, Ada!\n2\n"} -->
```manuscript
type Customer:
    name: String
    active: Bool

fn welcome(customer: Customer) String:
    return "Welcome, {customer.name}!"

export fn main() Int:
    let customer = Customer(name: "Ada", active: true)
    let greeting = welcome(customer)
    let count: Int = 3
    var remaining = count
    remaining -= 1
    print(greeting)
    print(remaining)
    return 0
```

```text
Welcome, Ada!
2
```

## Destructuring

Unpack positions or named fields:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada, Lin: Ada, ada@example.com\n"} -->
```manuscript
type Customer:
    name: String
    email: String

export fn main() Int:
    let names = ["Ada", "Lin"]
    let customer = Customer("Ada", "ada@example.com")
    let [first_name, second_name] = names
    let {name, email: customer_email} = customer
    print("{first_name}, {second_name}: {name}, {customer_email}")
    return 0
```

```text
Ada, Lin: Ada, ada@example.com
```

`[...]` binds positions; `{field: local}` renames a record field. Field shorthand and nesting work; parenthesized positional bindings do not. See [destructuring bindings](../types/destructuring.md).

## Scope and shadowing

- A local name cannot be declared twice in one scope, and a nested scope (a block, match arm, loop, or closure parameter) cannot reuse the name of an enclosing local or parameter: `ms check` rejects the shadowing binding. Rename one of them. A name starting with `_` is exempt.
- A local or match payload that is never read is an error (`local binding x is never read`); remove it or start the name with `_`. A `var` that is only assigned counts as unread, and unfinished code in the editor is not reported.
- Every local needs an initial value. The name is visible only after its initializer.
- Locals are visible in source order; module declaration signatures may refer forward.
- A `var` keeps the type from its annotation or initializer; later values must fit it.
- Assignment targets a `var` binding or a field reached through mutable storage. `let` is immutable including contents; mutation through a parameter or receiver requires `var`. Collection methods that mutate require a mutable receiver and return Unit.

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["expected Int, found Float"]} -->
```manuscript
fn example() Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  // Rejected: Float cannot replace Int.
```

The diagnostic includes `expected Int, found Float`.

`+=`, `-=`, `*=`, `/=`, and `%=` update a `var` or record field: `remaining -= 1` means `remaining = remaining - 1`. The right side is one operand (`total -= a - b` subtracts the difference), and `+=` also appends text. See the [statement grammar](grammar.md#statements-and-patterns).

Only a simple name accepts a type annotation. Destructuring infers each local; elisions, rest/default patterns, destructuring assignment, and pattern annotations are rejected. See [type compatibility](../types/compatibility.md).

## Reassignment and references

A `let` record or collection cannot be mutated. Primitives copy implicitly. A string, record or collection has one owner: `let y = x` and `let y = x.part` borrow it (`x` stays readable and cannot change while `y` is used), `var y = x.part` borrows it exclusively so `y.append(1)` changes `x.part`, and `var y = x` moves it when `x` is not itself a `var`. A value moves into a moving position (a record field, a collection, a `return` of something that is not a parameter) at its last use; `.clone()` makes an explicit deep copy wherever an independent value is wanted. See [mutation and references](../types/references.md).

`var n = r.n` of a primitive copies the number: `n += 1` leaves `r.n` as it was. A call that returns a part of its argument returns a borrow of it, so `var xs = b.list()` changes `b`'s list and `var xs = f()` of a function building a new value owns it.

Reassigning an owning `var` drops the previous value and closes resources it held. A live borrow prevents that reassignment. The replacement closes when its owning scope ends unless it moves to another owner. See [mutation and references](../types/references.md).
