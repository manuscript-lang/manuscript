+++
title = "Enums"
weight = 2
+++

# Enums

Use an enum (a tagged union) when a value is exactly one of several declared cases, each with its own data.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Payment.Paid(receipt-42)\n"} -->
```manuscript
enum Payment:
    Paid(receipt: String)
    Declined(reason: String)
    Pending(reference: String)

export fn main() Int:
    let payment: Payment = Paid("receipt-42")
    print(payment)
    return 0
```

```text
Payment.Paid(receipt-42)
```

Enums are tagged and exhaustively matched.

- At least one case; case names are unique, and payload field names are unique within a case.
- A case may have no payload: `Missing`.
- Payload types are explicit; fields have no defaults.
- `enum` bodies contain only bare variant names with optional payload parameters; record fields belong in a `type` and methods in an `impl` block.

Migration: replace `type Choice:` with `enum Choice:` when its body declares cases. Then remove `case` before each variant. Both legacy spellings are rejected with diagnostics explaining the new spelling. Records keep `type`; constructors and exhaustive matching keep the same behavior. `enum` is reserved, so rename existing identifiers with that spelling. `case` is no longer reserved: `case`, `case(value: Int)`, and record field `case: Int` are ordinary names in their respective contexts.

## Construction and identity

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Payment.Paid(receipt-42)\nPayment.Declined(Card rejected)\n"} -->
```manuscript
enum Payment:
    Paid(receipt: String)
    Declined(reason: String)
    Pending(reference: String)

export fn main() Int:
    let payment = Payment.Paid("receipt-42")
    let declined: Payment = Declined("Card rejected")
    print(payment)
    print(declined)
    return 0
```

```text
Payment.Paid(receipt-42)
Payment.Declined(Card rejected)
```

- `Type.Case` names a case of that nominal type. It is not a module path: import the type, then qualify its case.
- A single-payload case may omit its label, such as `ok(3)`.
- Multi-payload constructors follow the ordinary [call rules](../functions/declarations-and-calls.md#argument-names); every payload field appears exactly once.
- Payloadless cases are values (`State.Ready`), without `()`. Tags do not convert to integers.

Ordinary name lookup runs first: a local, declaration, or import with that spelling wins over case shorthand. Otherwise an unqualified case name must match exactly one case among visible enums. If several declare it, qualify it, even with an annotation. An expected enum type can supply generic arguments once the case is unique; a qualified case that contradicts the expected type is rejected, and matching payload shapes never make distinct enums compatible.

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["ambiguous alternative case Ready","expected LeftState, found RightState"]} -->
```manuscript
enum LeftState:
    Ready

enum RightState:
    Ready

export fn main() Int:
    let left: LeftState = LeftState.Ready
    // Rejected: two visible Ready cases, even with an annotation.
    let annotated: LeftState = Ready
    // Rejected: two visible Ready cases.
    let ambiguous = Ready
    // Rejected: a different nominal enum.
    let wrong: LeftState = RightState.Ready
    return 0
```

The diagnostic includes `ambiguous alternative case Ready`, `expected LeftState, found RightState`.

After `let Ready = LeftState.Ready`, `Ready` refers to that binding, not case lookup.

Type arguments attach to the enum, never the case: write `Choice[Int].Found(value: 1)`. `Found[Int](value: 1)` and `Choice.Found[Int](value: 1)` are rejected; unqualified `Found(value: 1)` may infer arguments or use a complete expected `Choice[Int]`. This also holds for standard Optional/Result cases.

Exporting an enum exposes every case and payload field. Payload types follow the [public surface](records.md#public-data-surfaces) and [recursive data](records.md#recursive-data) rules for records.

## Handling a case

A [match](../control-flow/pattern-matching.md) selects the case and binds its payload; it must cover every case. Patterns resolve against the scrutinee's enum type.

There are no implicit unions or nullable references. Declare an enum, or use [Optional](optionals.md) for absence.

## Resource payloads

A payload borrowed by a match keeps its owner available while it is used. A match on an owned value at its last use can move a payload to a new owner, transferring its cleanup duty. See [references inside other values](references.md).
