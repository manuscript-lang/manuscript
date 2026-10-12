+++
title = "Bindings and scope"
weight = 7
+++

# Bindings and scope

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A binding gives a name to a value. Choose `let` when the name should keep its value and `var` when you need to assign a replacement.

```manuscript
let count: Int = 3
var remaining = count
remaining = remaining - 1
```

`let` prohibits reassignment; `var` permits it. In this example, `count` remains 3 and `remaining` becomes 2.

## Local type inference

Function parameters and return types are explicit; local annotations are optional. The initializer `3` infers `Int`, so `let count = 3` and `let count: Int = 3` select the same type. A constructor can also provide the information needed to infer a local type.

The following continues the `Customer` and `welcome` declarations in [source structure and syntax](syntax.md):

```manuscript
let customer = Customer(name: "Ada", active: true)
let greeting = welcome(customer: customer)
let count: Int = 3
var remaining = count
remaining = remaining - 1
```

## Destructuring

Bindings use JavaScript-style positional and record patterns:

```manuscript
let [first_name, second_name] = names
let {name, email: customer_email} = customer
```

Use `[...]` for positions and `{field: local}` to rename a record field. Patterns also support field shorthand and nesting. Parenthesized positional bindings are not supported. See [destructuring bindings](destructuring.md) for static shape checks and list behavior.

## Scope and shadowing

A scope is the part of a program where a name is visible. You cannot declare the same local name twice in one scope. A nested block may declare its own name that hides an outer one; this is called shadowing. Assigning to a `var` updates an existing binding, while declaring a name inside a nested block creates a separate binding.

Every local declaration needs an initial value. The new name becomes visible only after that initializer is checked, so a declaration cannot use its own new name to compute the initial value. If an outer scope already has the same name, the initializer can still use that outer binding. Local names become available in source order; module declaration signatures can refer forward to later declarations.

A var keeps the type chosen by its annotation or initializer. Later values must fit that same type. Assigning a Float to an Int var does not change the var's type or create a union.

Assignment targets an existing `var` binding or a record field, such as `customer.name`. Record fields may be assigned through `let` bindings, parameters, and `self`. You cannot reassign parameters, `let` bindings, destructuring patterns, or collection positions with assignment syntax; collection methods update their contents.

```manuscript
fn example() -> Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  # Rejected: Float cannot replace Int.
```

Only a simple name binding accepts a type annotation. Destructuring patterns infer each local from the checked initializer; elisions, rest/default patterns, destructuring assignment, and pattern annotations are rejected. See [type compatibility](../types/compatibility.md) for contextual constructor inference.

## Reassignment and references

Binding mutability and object mutation are separate. A `var` holding a [record](../types/records.md) can receive another record. Both `let` and `var` bindings permit updating that record's fields. Assignment of a record or collection retains the same instance; `.clone()` creates a separate shallow copy.

Assignment replaces the value of the binding; it does not close the previous resource or invalidate aliases. `with` registers a fixed resource for cleanup and uses an immutable binding. See [ordinary references](../../ownership-and-cleanup/values/references.md).

[Previous: Expressions and operators](expressions.md) · [Next: Destructuring bindings](destructuring.md)
