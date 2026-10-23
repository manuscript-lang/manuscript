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

## Grouping bindings

`let (` and `var (` declare several bindings of one kind, one per line, indented four spaces, with the closing `)` aligned with the keyword. Each entry is the same as a single binding, including an optional annotation or a destructuring pattern, and later entries see earlier ones.

```manuscript
let (
    name = "Ada"
    active: Bool = true
)
var (
    attempts = 0
    limit = attempts + 3
)
```

A group is only a layout: entries are separate bindings with their own scope rules, and the formatter keeps the group together. Separate entries by lines, not commas, and use `let [a, b] = pair` to destructure. A group cannot sit in an inline body such as `if ready: let (`.

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
- Assignment targets a `var` binding or a field reached through mutable storage. `let` is immutable including contents; mutation through a parameter or receiver requires `var`. Collection methods that mutate require a mutable receiver and return Unit.

```manuscript
fn example() Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  # Rejected: Float cannot replace Int.
```

`+=`, `-=`, `*=`, `/=`, and `%=` update a `var` or record field: `remaining -= 1` means `remaining = remaining - 1`. The right side is one operand (`total -= a - b` subtracts the difference), and `+=` also appends text. See the [statement grammar](grammar.md#statements-and-patterns).

Only a simple name accepts a type annotation. Destructuring infers each local; elisions, rest/default patterns, destructuring assignment, and pattern annotations are rejected. See [type compatibility](../types/compatibility.md).

## Reassignment and references

A `let` record or collection cannot be mutated. Scalars copy implicitly; strings and other owned values move at their last use into consuming positions, while place bindings can borrow. `.clone()` makes an explicit deep copy; see [mutation and references](../types/references.md).

`var x = place` is the exception: when the value is a field or element of another `var` (`var n = r.n`, `var xs = r.xs`, `var head = rows[0]`), `x` is a mutable borrow of that part for every type, so `n += 1` changes `r.n` just as `xs.append(1)` changes `r.xs`. To get an independent scalar, bind it with `let` first (`let start = r.n` then `var n = start`); to get an independent collection or record, use `.clone()`. A call result has no place to borrow, so `var n = f()` owns the value.

Assignment does not close the previous resource or invalidate aliases. `with` registers a fixed resource for cleanup using an immutable binding. See [mutation and references](../types/references.md).
