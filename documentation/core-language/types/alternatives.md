+++
title = "Alternatives"
weight = 2
+++

# Alternatives

Use an alternative when a value is exactly one of several declared cases, each with its own data.

```manuscript
type Payment:
    case Paid(receipt: String)
    case Declined(reason: String)
    case Pending(reference: String)
```

Alternatives are tagged and exhaustively matched.

- At least one case; case names are unique, and payload field names are unique within a case.
- A case may have no payload: `case Missing`.
- Payload types are explicit; fields have no defaults.
- Record fields and cases cannot be mixed in one `type`.

## Construction and identity

```manuscript
let payment = Payment.Paid("receipt-42")
let declined: Payment = Declined("Card rejected")
```

- `Type.Case` names a case of that nominal type. It is not a module path: import the type, then qualify its case.
- A single-payload case may omit its label, such as `ok(3)`.
- Multi-payload constructors follow the ordinary [call rules](../functions/declarations-and-calls.md#argument-names); every payload field appears exactly once.
- Payloadless cases are values (`State.Ready`), without `()`. Tags do not convert to integers.

Ordinary name lookup runs first: a local, declaration, or import with that spelling wins over case shorthand. Otherwise an unqualified case name must match exactly one case among visible alternatives. If several declare it, qualify it, even with an annotation. An expected alternative type can supply generic arguments once the case is unique; a qualified case that contradicts the expected type is rejected, and matching payload shapes never make distinct alternatives compatible.

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

After `let Ready = LeftState.Ready`, `Ready` refers to that binding, not case lookup.

Type arguments attach to the alternative, never the case: write `Choice[Int].Found(value: 1)`. `Found[Int](value: 1)` and `Choice.Found[Int](value: 1)` are rejected; unqualified `Found(value: 1)` may infer arguments or use a complete expected `Choice[Int]`. This also holds for standard Optional/Result cases.

Exporting an alternative exposes every case and payload field. Payload types follow the [public surface](records.md#public-data-surfaces) and [recursive data](records.md#recursive-data) rules for records.

## Handling a case

A [match](../control-flow/pattern-matching.md) selects the case and binds its payload; it must cover every case. Patterns resolve against the scrutinee's alternative type.

There are no implicit unions or nullable references. Declare an alternative, or use [Optional](optionals.md) for absence.

## Resource payloads

Matching a payload does not invalidate the original, register cleanup, or extend a resource's lifetime. See [references inside other values](references.md).
