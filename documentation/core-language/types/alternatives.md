+++
title = "Enums"
weight = 2
+++

# Enums

Use an enum (a tagged union) when a value is exactly one of several declared cases, each with its own data. A payment can be paid, declined, or pending. A paid payment needs a receipt; a declined payment needs a reason. Putting the data inside each case keeps those possibilities together, so the program cannot accidentally pair a paid status with only a decline reason.

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

## Handling a case

Constructing `Paid("receipt-42")` selects the `Paid` case and stores its receipt. To turn that value into a message, use `match`: each arm handles one case and gives its payload a local name. The message can use that case's data without checking whether an unrelated field happens to be present.

Save this complete program as `payment.ms` and run `ms run payment.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Paid: receipt-42\nDeclined: Card rejected\nPending: order-3\n","filename":"payment.ms"} -->
```manuscript
enum Payment:
    Paid(receipt: String)
    Declined(reason: String)
    Pending(reference: String)

fn describe(payment: Payment) String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"
        Pending(reference):
            return "Pending: {reference}"

export fn main() Int:
    print(describe(Paid("receipt-42")))
    print(describe(Declined("Card rejected")))
    print(describe(Pending("order-3")))
    return 0
```

```text
Paid: receipt-42
Declined: Card rejected
Pending: order-3
```

`describe` returns a message for every case, and only the selected arm runs. The receipt binding belongs to the `Paid` arm; it does not exist in the other arms. Patterns resolve against the value being matched, so the arm names do not need a `Payment.` prefix.

If you add `Refunded(receipt: String)` to `Payment`, `describe` stops passing `ms check` until it handles the new case. That is useful when every new state needs a deliberate behavior. A final wildcard can cover remaining cases when they truly share one action; see [exhaustive matching](../control-flow/pattern-matching.md#exhaustiveness) for that choice and its tradeoffs.

There are no implicit unions or nullable references. Declare an enum for distinct states, or use [Optional](optionals.md) for absence.

## Declaration rules

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

## Resource payloads

A payload borrowed by a match keeps its owner available while it is used. A match on an owned value at its last use can move a payload to a new owner, transferring its cleanup duty. See [references inside other values](references.md).
