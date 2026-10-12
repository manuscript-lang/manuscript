+++
title = "Pattern matching"
weight = 26
+++

# Pattern matching

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `match` to handle the cases of an alternative type. Each branch can give names to the data carried by its case. For example, a payment may be paid, declined, or pending, and each outcome needs different handling.

A match accepts tagged alternative types, including `Optional` and `Result`. Matching numeric or Boolean literals, guards, ranges, nested case patterns, and combined patterns is rejected. `match` is a statement; it cannot initialize a binding as an expression. The scrutinee evaluates once.

The following function handles the `Payment` type declared in [alternatives](../types/alternatives.md):

```manuscript
fn describe(payment: Payment) -> String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"
        Pending(reference):
            return "Pending: {reference}"
```

## Payload patterns

Case payloads bind positions in the declaration's field order. A pattern must give exactly one identifier or `_` placeholder per payload field. Pattern payloads are positional even though constructors always use named fields. Nullary cases use a bare case name without `()`.

```manuscript
type Position:
    case Point(x: Int, y: Int)
    case Unknown

fn horizontal(position: Position) -> Int:
    match position:
        Position.Point(horizontal_value, _):
            return horizontal_value
        Position.Unknown:
            return 0
```

`Point(x: local, y: other):` is rejected at parsing. `Point(x):` is rejected for wrong arity. Repeated binding identifiers are rejected, while `_` can occur repeatedly because it creates no name. Each arm's payload bindings and body share a lexical scope nested inside the enclosing scope.

An unqualified case in a pattern resolves within the scrutinee's alternative type. A qualified case must belong to that exact type. `Other.Point(...)` cannot match `Position`, even when its payload types have the same shape. Constructor-expression name lookup instead follows [alternative construction](../types/alternatives.md).

## Exhaustiveness

Match cases bind data without fallthrough; missing alternatives are compile errors. Wildcard cases must be explicit.

Every case in the example returns its own description. Running the `Paid` branch does not continue into `Declined` or `Pending`. The compiler checks that all alternatives are accounted for.

`_:` is the wildcard arm. It is permitted once, must be last, binds nothing, and covers every case not already handled. Duplicate cases, unknown cases, an arm after the wildcard, and a wildcard after all cases have been explicitly covered are rejected as invalid or unreachable arms. Qualified and unqualified spellings of the same case count as duplicates.

```manuscript
fn paid(payment: Payment) -> Bool:
    match payment:
        Paid(_):
            return true
        _:
            return false
```

Adding a case to an alternative invalidates exhaustive matches that lack a wildcard. A match with a wildcard remains exhaustive; its wildcard handles the new case. Return completeness is checked across all reachable arms using the [function return rules](../functions/declarations-and-calls.md#unit-and-never).

## Optional and result values

[Optional](../types/optionals.md) and [Result](../errors/results.md) are also alternative types. Matching an optional distinguishes a present value from absence. Matching a result distinguishes success from an expected failure and lets the caller decide what to do with each.

## Matching resource references

Matching binds ordinary payload values and references. No binding is consumed, and matching does not register resource cleanup. [Destructuring bindings](../basics/destructuring.md) use brackets or braces; alternative match cases retain their `Case(payload)` syntax. See [aggregate references](../../ownership-and-cleanup/values/aggregates.md).

[Previous: Loops](loops.md) · [Next: Expected failures with Result](../errors/results.md)
