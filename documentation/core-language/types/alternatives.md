+++
title = "Enums"
weight = 2
+++

# Enums

Use an enum (a tagged union) when a value is exactly one of several declared cases, each with its own data.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
enum Payment:
    Paid(receipt String)
    Declined(reason String)
    Pending(reference String)
```

Enums are tagged and exhaustively matched.

- An enum has at least one case. Case names are unique, and payload field names are unique within a case.
- A case may have no payload: `Missing`.
- Payload types are explicit, and payload fields have no defaults.
- An `enum` body holds only case names with optional payload parameters. Fields belong in a `type`, and methods are receiver methods, `fn Enum.name(...)`.

Migration from the old syntax: replace `type Choice:` with `enum Choice:` when its body declares cases, then remove `case` before each case name. The compiler rejects both old spellings with a diagnostic that names the new one. Constructors and exhaustive matching behave as before, and `type` still declares types.

`enum` is a reserved word, so rename any existing identifier spelled `enum`. `case` is no longer reserved: `case`, `case(value Int)`, and a field `case Int` are ordinary names in their contexts.

## Construction and identity

<!-- manuscript-example: {"mode":"fragment","context":"enum Payment:\n    Paid(receipt String)\n    Declined(reason String)","given":[]} -->
```manuscript
payment := Payment.Paid("receipt-42")
declined Payment := Declined("Card rejected")
```

- `Type.Case` names a case of that nominal type. It is not a module path: import the type, then qualify its case.
- A single-payload case may omit its label, such as `ok(3)`.
- Multi-payload constructors follow the ordinary [call rules](../functions/declarations-and-calls.md#argument-names); every payload field appears exactly once.
- Payloadless cases are values (`State.Ready`), without `()`. Tags do not convert to integers.

Ordinary name lookup runs first: a local, declaration, or import with that spelling wins over case shorthand. Otherwise an unqualified case name must match exactly one case among the visible enums. If several enums declare it, qualify it, even when an annotation names the enum.

Once the case is unique, an expected enum type can supply generic arguments. A qualified case that contradicts the expected type is rejected, and matching payload shapes never make distinct enums compatible.

<!-- manuscript-example: {"mode":"error","contains":"ambiguous alternative case","given":[]} -->
```manuscript
enum LeftState:
    Ready

enum RightState:
    Ready

left LeftState := LeftState.Ready
// Rejected: two visible Ready cases, even with an annotation.
annotated LeftState := Ready
// Rejected: two visible Ready cases.
ambiguous := Ready
// Rejected: a different nominal enum.
wrong LeftState := RightState.Ready
```

After `Ready := LeftState.Ready`, `Ready` refers to that binding, not case lookup.

Type arguments attach to the enum, never the case: write `Choice[Int].Found(value: 1)`. `Found[Int](value: 1)` and `Choice.Found[Int](value: 1)` are rejected; unqualified `Found(value: 1)` may infer arguments or use a complete expected `Choice[Int]`. The same holds for the standard `Optional` and `Result` cases.

Exporting an enum exposes every case and payload field. Payload types follow the [public surface](named-types.md#public-data-surfaces) and [recursive data](named-types.md#recursive-data) rules for types.

## Handling a case

A [match](../control-flow/pattern-matching.md) selects the case and binds its payload; it must cover every case. Patterns resolve against the scrutinee's enum type.

There are no implicit unions or nullable references. Declare an enum, or use [Optional](optionals.md) for absence.

## Resource payloads

A payload that a match borrows keeps its owner available while the payload is in use. A match on an owned value at its last use can move a payload to a new owner, which takes over its cleanup duty. See [references inside other values](references.md).
