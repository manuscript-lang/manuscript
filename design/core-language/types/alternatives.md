+++
title = "Alternatives"
weight = 13
+++

# Alternatives

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use an alternative type when a value can be one of several declared cases. For example, a payment can be paid, declined, or pending. Each case may carry its own data, such as a receipt or a reason.

```manuscript
type Payment:
    case Paid(receipt: String)
    case Declined(reason: String)
    case Pending(reference: String)
```

Alternatives are tagged and exhaustively matched. `Paid`, `Declined`, and `Pending` are different cases of `Payment`, even though each carries text.

A declaration has at least one case. Case names are unique within the declaration; payload field names are unique within each case. A case may have no payload, written `case Missing`. Payload types are explicit and fields have no defaults. Record fields and cases cannot be mixed in one `type` declaration. Operation signatures belong to `interface` declarations.

## Construction and identity

```manuscript
let payment = Payment.Paid(receipt: "receipt-42")
let declined: Payment = Declined(reason: "Card rejected")
```

`Type.Case` identifies a case of that nominal type. Payload constructors supply every payload field by name exactly once; missing, duplicate, and unknown fields are errors. Payloadless cases are values such as `State.Ready`, without `()`. Tags do not implicitly convert to integers.

This qualification names a visible type and its case, not a module namespace. Modules import individual symbols; `customers.Customer` is not a type path introduced by importing a module. Import the nominal type name itself and qualify its case as `Type.Case`.

Ordinary lexical name lookup happens first. A local binding, ordinary declaration, or imported symbol with the spelling is used before case shorthand is considered. If ordinary lookup finds nothing, an unqualified constructor case name must identify exactly one case among visible nominal alternative declarations (declared or individually imported). If multiple visible types declare it, qualification is required even when an annotation supplies an expected type. An expected alternative application can supply generic arguments after a unique case is resolved. A qualified case inconsistent with the expected type is rejected. Matching payload shapes do not make distinct alternatives compatible.

Qualification still resolves `Type` through ordinary lookup. A local value shadowing that name does not act as a module namespace or expose the hidden type's cases.

```manuscript
type LeftState:
    case Ready

type RightState:
    case Ready

let left: LeftState = LeftState.Ready
# Rejected: two visible Ready cases, even with an annotation.
let annotated: LeftState = Ready
# Rejected: two visible Ready cases.
let ambiguous = Ready
# Rejected: a different nominal alternative.
let wrong: LeftState = RightState.Ready
```

Inside a scope with `let Ready = LeftState.Ready`, subsequent `Ready` expressions refer to that binding rather than retrying ambiguous case lookup. An incompatible expected type rejects the binding's type; it does not choose another type's case instead.

Generic qualification includes type arguments: `Choice[Int].Found(value: 1)`. Exporting an alternative exposes every case and payload field. Payload types follow the [public surface](records.md#public-data-surfaces) and [recursive layout](records.md#recursive-data) rules for records.

Type arguments attach to the nominal alternative, never to the case name. `Found[Int](value: 1)` and `Choice.Found[Int](value: 1)` are rejected. Unqualified `Found(value: 1)` may use argument inference or a complete expected `Choice[Int]` after case lookup resolves uniquely; explicit arguments use the single spelling `Choice[Int].Found(value: 1)`. These rules also apply to qualified standard Optional/Result cases.

## Handling a case

A [match](../control-flow/pattern-matching.md) selects the case and binds its payload. Code handling a payment must account for all three possibilities; adding another case requires the exhaustive matches to be reviewed.

Match patterns resolve cases against the scrutinee's known alternative type. Payload bindings are patterns rather than named call arguments. Their syntax is specified in [pattern matching](../control-flow/pattern-matching.md).

There is no general implicit union construction or nullable reference type. Declare the set of possibilities as an alternative type, or use [Optional](optionals.md) for absence.

## Resource payloads

Payloads retain ordinary values and references. Matching or extracting a resource reference does not invalidate the original value, register cleanup, or extend its open lifetime. See [aggregate references](../../ownership-and-cleanup/values/aggregates.md).

[Previous: Records and nominal types](records.md) · [Next: Optional values](optionals.md)
