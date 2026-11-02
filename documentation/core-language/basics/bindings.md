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

- A local name cannot be declared twice in one scope, and a nested scope (a block, match arm, loop, or closure parameter) cannot reuse the name of an enclosing local or parameter: `ms check` rejects the shadowing binding. Rename one of them. A name starting with `_` is exempt.
- A local or match payload that is never read is an error (`local binding x is never read`); remove it or start the name with `_`. A `var` that is only assigned counts as unread, and unfinished code in the editor is not reported.
- Every local needs an initial value. The name is visible only after its initializer.
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

A `let` record or collection cannot be mutated. Primitives copy implicitly. A string, record or collection has one owner: `let y = x` and `let y = x.part` borrow it (`x` stays readable and cannot change while `y` is used), `var y = x.part` borrows it exclusively so `y.append(1)` changes `x.part`, and `var y = x` moves it when `x` is not itself a `var`. A value moves into a consuming position (a record field, a collection, a `return` of something that is not a parameter) at its last use; `.clone()` makes an explicit deep copy wherever an independent value is wanted. See [mutation and references](../types/references.md).

`var n = r.n` of a primitive copies the number: `n += 1` leaves `r.n` as it was. A call that returns a part of its argument lends it, so `var xs = b.list()` changes `b`'s list and `var xs = f()` of a function building a new value owns it.

Assignment does not close the previous resource or invalidate aliases. A resource bound with `let` or `var` is closed when its scope ends. See [mutation and references](../types/references.md).
