+++
title = "Bindings and scope"
weight = 7
+++

# Bindings and scope

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A binding gives a name to a value. Choose `let` when the name should keep its value and `var` when you need to assign a replacement.

```text
let count: Int = 3
var remaining = count
remaining = remaining - 1
```

`let` prohibits reassignment; `var` permits it. In this example, `count` remains 3 and `remaining` becomes 2.

## Local type inference

Function parameters and return types are explicit; local annotations are optional. The initializer `3` infers `Int`, so `let count = 3` and `let count: Int = 3` select the same type. A constructor can also provide the information needed to infer a local type.

The following continues the `Customer` and `welcome` declarations in [source structure and syntax](syntax.md):

```text
let customer = Customer(name: "Ada", active: true)
let greeting = welcome(customer: customer)
let count: Int = 3
var remaining = count
remaining = remaining - 1
```

## Destructuring

Bindings use JavaScript-style positional and record patterns:

```text
let [resA, resB] = try parallel(tasks: [first, second])
let {name, email: customer_email} = customer
```

The parallel fragment needs an enclosing `Result[U, ExecutionError]` function; see the [complete example](../../concurrency/parallel.md). Use `[...]` for positions and `{field: local}` to rename a record field. Patterns also support field shorthand and nesting. Parenthesized positional bindings are not supported. See [destructuring bindings](destructuring.md) for static shape checks and list behavior.

## Scope and shadowing

Shadowing within one lexical scope is rejected. Nested scopes may shadow outer bindings. An assignment to a `var` changes an existing binding; a declaration in a nested scope introduces a binding with its own lifetime.

Every local binding has an initializer. Its names become visible only after the initializer has been checked; it cannot refer to the names it is introducing. If an outer binding has that name, the initializer can refer to the outer binding before the new nested name shadows it. Locals resolve in source order, unlike module declaration signatures, which allow forward references.

A `var`'s type is fixed by its annotation or first initializer. Later assignments must have that same compatible type; a binding never widens into a union or changes numeric type. Assignment targets are existing mutable local names only. Record fields, collection elements, patterns, parameters, and immutable bindings cannot be reassigned.

```text
fn example() -> Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  # Rejected: Float cannot replace Int.
```

Only a simple name binding accepts a type annotation. Destructuring patterns infer each local from the checked initializer; elisions, rest/default patterns, destructuring assignment, and pattern annotations are rejected. See [type compatibility](../types/compatibility.md) for contextual constructor inference.

## Reassignment and references

A mutable binding does not make the value's fields mutable. A `var` holding a [record](../types/records.md) can receive another record, while each record remains immutable.

Assignment replaces the value of the binding; it does not close the previous resource or invalidate aliases. `with` registers a fixed resource for cleanup and uses an immutable binding. See [ordinary references](../../ownership-and-cleanup/values/references.md).

[Previous: Expressions and operators](expressions.md) · [Next: Destructuring bindings](destructuring.md)
