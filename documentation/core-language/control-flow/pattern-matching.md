+++
title = "Pattern matching"
weight = 3
+++

# Pattern matching

`match` handles each case of an enum type and names the case's data. Use it for your own enums and contract views. For an Optional payload or Result success, use `if let` or `try` as described [below](#optional-and-result-values).

`match` is an expression: it can initialize a binding, be an argument, or stand alone with its result discarded. The scrutinee evaluates once and only the selected arm runs. Save this complete example as `payment.ms` and run `ms run payment.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Paid: receipt-42\n","filename":"payment.ms"} -->
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
    print(describe(Payment.Paid("receipt-42")))
    return 0
```

```text
Paid: receipt-42
```

Each arm handles one case and gives its payload a local name. A newly added case needs an arm unless the match has a wildcard. Guards, ranges, nested case patterns and combined patterns are rejected; use another statement after binding the payload. Literal arms are described in [matching literals](#matching-literals).

## Keep match flow flat

Nested `match` is an anti-pattern. Bind the outer payload with an early exit, propagate with `try`, use Optional methods, or call a small helper (the contract handler below shows a helper).

- `ms lint` reports **MSL107** at each inner match, including inside inline callbacks. Helpers and sequential matches are fine. The checker still accepts nesting; this is style only.
- An `Optional` has no `some` pattern: the present arm is a bare lowercase name beside `none:` (`v:` binds the payload). A two-arm payload/`none` match is **MSL108**. Use [`if let`](conditionals.md#unwrapping-an-optional-or-result), `get(default)`, or `map`.

Matching a `Result` with only `ok` and `error` arms is flagged the same way as advisory **MSL109**. Use `try`, `if let value = result:` with `else:`, or a Result method such as `get(default)`, `is_error`, or `err`.

## Matching literals

A `match` on an `Int`, `String`, or `Bool` takes literal arms: number literals (with an optional `-`), plain text literals, `true`, and `false`. Arms are tested in order; each value may appear once. A final `_` is required unless `true` and `false` are both covered. Arms bind nothing.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"none\none\nmany\n"} -->
```manuscript
fn name(count: Int) String:
    match count:
        0: return "none"
        1: return "one"
        _: return "many"

export fn main() Int:
    print(name(0))
    print(name(1))
    print(name(4))
    return 0
```

```text
none
one
many
```

Computed values, interpolated text, ranges, and `Float` scrutinees are not literal patterns; use `if` and `else if`.

## Arm values

An arm may hold statements then a final expression, which is its value; ending in a statement gives `Unit`. Value-producing arms must share a compatible type, taken from the annotation or expected type, or else from the arms themselves. Arms that exit via `return`, `break`, `continue`, or `Never` contribute no value.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"42\nInvalid amount\n"} -->
```manuscript
enum Cents:
    Valid(amount: Int)
    Invalid

fn total(cents: Cents) Int!:
    let amount = match cents:
        Valid(value):
            value
        Invalid:
            return error(Error("Invalid amount"))
    return ok(amount)

fn report(cause: Error) Error:
    print(cause.message)
    return cause.clone()

fn show_total(cents: Cents) Unit:
    if let value = total(cents).map_error(report):
        print(value)

export fn main() Int:
    show_total(Valid(42))
    show_total(Invalid)
    return 0
```

```text
42
Invalid amount
```

`return` exits the enclosing function even from inside another expression, running cleanup; `break` and `continue` target the enclosing loop; an anonymous function has its own return boundary.

Short arms put the value after the colon (`none: 0`). End an effect-only arm with `unit` if its last call returns something else. A standalone match discards its result, so arms need not agree; a used result needs every arm to produce it. An empty arm or block is `unit`; there is no `pass`.

## Payload patterns

Payloads bind by position in field order: exactly one identifier or `_` per field, even though constructors use named fields. Nullary cases are a bare name without `()`.

Lowercase variant names, including `case`, follow the same rule. A lone lowercase arm binds a payload only when matching an `Optional`; on another enum it names a payloadless variant.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"3\n0\n"} -->
```manuscript
enum Position:
    Point(x: Int, y: Int)
    Unknown

fn horizontal(position: Position) Int:
    match position:
        Position.Point(horizontal_value, _):
            return horizontal_value
        Position.Unknown:
            return 0

export fn main() Int:
    print(horizontal(Position.Point(3, 4)))
    print(horizontal(Position.Unknown))
    return 0
```

```text
3
0
```

- `Point(x: local, y: other):` is a parse error; `Point(x):` is an arity error. Repeated names are rejected; `_` may repeat.
- Payload bindings and the arm body share a nested scope.
- An unqualified case resolves within the scrutinee's type; a qualified case must belong to that exact type (`Other.Point(...)` never matches `Position`). Constructors resolve per [alternative construction](../types/alternatives.md).
- Payload names always bind fresh. `error(NotFound)` matches every error and does not test for `NotFound`; bind `error(cause)` and pass `cause` to a helper that matches the cases.

`ms lint` reports **MSL106** (a lint error; `ms check` accepts it) when a capitalized payload name coincides with a known case or type name. Use a name like `cause` or `_cause`.

## Exhaustiveness

Arms never fall through, and a missing case is a compile error. `_:` is the wildcard: allowed once, last, binds nothing, and covers the remaining cases. Rejected: duplicate or unknown cases (qualified and unqualified spellings of one case are duplicates), an arm after the wildcard, and a wildcard after every case is covered.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"true\nfalse\n"} -->
```manuscript
enum Payment:
    Paid(receipt: String)
    Declined(reason: String)
    Pending(reference: String)

fn paid(payment: Payment) Bool:
    match payment:
        Paid(_):
            return true
        _:
            return false

export fn main() Int:
    print(paid(Paid("receipt-42")))
    print(paid(Pending("order-3")))
    return 0
```

```text
true
false
```

Adding a case breaks matches without a wildcard; a wildcard absorbs it. Return completeness follows the [function return rules](../functions/declarations-and-calls.md#unit-and-never).

## Optional and result values

[Optional](../types/optionals.md) and [Result](../errors/results.md) are alternatives, but do not match them. Use `if let value = expression:` for a value or success, `get(default)` for a default, `try` to propagate an error, and `is_error()` with `err()` to read a cause.

## Contract type patterns

A contract view keeps its concrete receiver. `ConcreteType(receiver)` recovers it for a particular implementation, and `_:` handles the rest. This is not a constructor call.

Save this declaration example as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"check","filename":"example.ms","stdout":"Checked example.ms\n"} -->
```manuscript
interface Shape:
    fn area() Int

type Square:
    side: Int

impl Shape for Square:
    fn area() Int: return self.side * self.side

fn describe(shape: Shape) String:
    match shape:
        Square(square): return "square {square.side}"
        _:
            return "area {shape.area()}"
```

```text
Checked example.ms
```

- The type is a local or imported nominal record or alternative with an explicit implementation of the scrutinee's exact contract.
- Give exactly one receiver name or `_`, even for a payloadless alternative. The binding has the concrete type. Native opaque receivers fall to the wildcard.
- Generic patterns name the full application: `Boxed[Int](value)` differs from `Boxed[String]`; an in-scope parameter may be an argument (`Boxed[T](value)`). The first arm matching the exact runtime type wins; duplicate patterns are rejected. A pattern cannot name another contract, a bare type parameter, or a single alternative case.
- A final wildcard is required because contracts are open. It binds nothing; use the original value for generic handling.
- The receiver is not copied, and matching adds no cleanup and catches no faults or cancellation. See [contract views](../types/contracts.md#interface-conversion).

## Matching resource references

Matching a borrowed value borrows its payloads. Matching an owned value at its last use can move its payloads, transferring responsibility for their cleanup. Unmoved resource parts still close; see [ownership](../types/references.md). [Destructuring](../types/destructuring.md) uses brackets or braces; match cases use `Case(payload)`. See [references](../types/references.md).
