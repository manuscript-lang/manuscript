+++
title = "Variables and scope"
weight = 2
+++

# Variables and scope

`let` bindings cannot be reassigned; `var` bindings can.

```manuscript
let count: Int = 3
var remaining = count
remaining -= 1
```

## Local type inference

Parameters and return types are explicit; local annotations are optional. `let count = 3` and `let count: Int = 3` are the same. Constructors also infer types. This continues the `Customer` and `welcome` declarations in [source files](syntax.md):

```manuscript
let customer = Customer(name: "Ada", active: true)
let greeting = welcome(customer)
let count: Int = 3
var remaining = count
remaining -= 1
```

## Destructuring

Unpack positions or named fields:

```manuscript
let [first_name, second_name] = names
let {name, email: customer_email} = customer
```

`[...]` binds positions; `{field: local}` renames a record field. Field shorthand and nesting work; parenthesized positional bindings do not. See [destructuring bindings](../types/destructuring.md).

## Scope and shadowing

- A local name cannot be declared twice in one scope. A nested block may declare the same name, which shadows the outer one.
- Every local needs an initial value. The name is visible only after its initializer, so the initializer may use an outer binding of the same name.
- Locals are visible in source order; module declaration signatures may refer forward.
- A `var` keeps the type from its annotation or initializer; later values must fit it.
- Assignment targets a `var` or a record field such as `customer.name`, including through `let` bindings, parameters, and `self`. Parameters, `let` bindings, destructured names, and collection positions cannot be reassigned; collection methods update contents.

```manuscript
fn example() -> Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  # Rejected: Float cannot replace Int.
```

`+=`, `-=`, `*=`, `/=`, and `%=` update a `var` or record field: `remaining -= 1` means `remaining = remaining - 1`. The right side is one operand (`total -= a - b` subtracts the difference), and `+=` also appends text. See the [statement grammar](grammar.md#statements-and-patterns).

Only a simple name accepts a type annotation. Destructuring infers each local; elisions, rest/default patterns, destructuring assignment, and pattern annotations are rejected. See [type compatibility](../types/compatibility.md).

## Reassignment and references

Binding mutability and object mutation are separate: a `let` record still allows field updates. Assigning a record or collection keeps the same instance; `.clone()` makes a shallow copy.

Assignment does not close the previous resource or invalidate aliases. `with` registers a fixed resource for cleanup using an immutable binding. See [mutation and references](../types/references.md).
