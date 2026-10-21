+++
title = "Pattern matching"
weight = 3
+++

# Pattern matching

`match` handles each case of an alternative type and names the case's data. Use it for your own alternatives and contract views. Avoid it on `Optional` and `Result` (see [below](#optional-and-result-values)). Literals, guards, ranges, nested case patterns, and combined patterns are rejected.

`match` is an expression: it can initialize a binding, be an argument, or stand alone with its result discarded. The scrutinee evaluates once and only the selected arm runs. This handles the `Payment` type from [alternatives](../types/alternatives.md):

```manuscript
fn describe(payment: Payment) String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"
        Pending(reference):
            return "Pending: {reference}"
```

## Keep match flow flat

Nested `match` is an anti-pattern. Bind the outer payload with an early exit, propagate with `try`, use Optional methods, or call a small helper (the contract handler below shows a helper).

- `ms lint` reports **MSL107** at each inner match, including inside inline callbacks. Helpers and sequential matches are fine. The checker still accepts nesting; this is style only.
- A two-arm `some`/`none` match on an `Optional` is **MSL108**. Use [`if let`](conditionals.md#unwrapping-an-optional-or-result), `get(default)`, or `map`.

Matching a `Result` with only `ok` and `error` arms is flagged the same way as advisory **MSL109**. Use `try`, `if let value = result:` with `else:`, or a Result method such as `get(default)`, `is_error`, or `err`.

## Arm values

An arm may hold statements then a final expression, which is its value; ending in a statement gives `Unit`. Value-producing arms must share a compatible type, taken from the annotation or expected type, or else from the arms themselves. Arms that exit via `return`, `break`, `continue`, or `Never` contribute no value.

```manuscript
import {TextError} from "@std/core.ms"
type Cents:
    case Valid(amount: Int)
    case Invalid

fn total(cents: Cents) Result[Int, TextError]:
    let amount = match cents:
        Valid(value):
            value
        Invalid:
            return error(TextError("Invalid amount"))
    return ok(amount)
```

`return` exits the enclosing function even from inside another expression, running cleanup; `break` and `continue` target the enclosing loop; an anonymous function has its own return boundary.

Short arms put the value after the colon (`none: 0`). End an effect-only arm with `unit` if its last call returns something else. A standalone match discards its result, so arms need not agree; a used result needs every arm to produce it. An empty arm is `unit`; there is no `pass`.

## Payload patterns

Payloads bind by position in field order: exactly one identifier or `_` per field, even though constructors use named fields. Nullary cases are a bare name without `()`.

```manuscript
type Position:
    case Point(x: Int, y: Int)
    case Unknown

fn horizontal(position: Position) Int:
    match position:
        Position.Point(horizontal_value, _):
            return horizontal_value
        Position.Unknown:
            return 0
```

- `Point(x: local, y: other):` is a parse error; `Point(x):` is an arity error. Repeated names are rejected; `_` may repeat.
- Payload bindings and the arm body share a nested scope.
- An unqualified case resolves within the scrutinee's type; a qualified case must belong to that exact type (`Other.Point(...)` never matches `Position`). Constructors resolve per [alternative construction](../types/alternatives.md).
- Payload names always bind fresh. `error(NotFound)` matches every error and does not test for `NotFound`; bind `error(cause)` and pass `cause` to a helper that matches the cases.

`ms lint` reports **MSL106** (a warning in the editor; `ms check` accepts it) when a capitalized payload name coincides with a known case or type name. Use a name like `cause` or `_cause`.

## Exhaustiveness

Arms never fall through, and a missing case is a compile error. `_:` is the wildcard: allowed once, last, binds nothing, and covers the remaining cases. Rejected: duplicate or unknown cases (qualified and unqualified spellings of one case are duplicates), an arm after the wildcard, and a wildcard after every case is covered.

```manuscript
fn paid(payment: Payment) Bool:
    match payment:
        Paid(_):
            return true
        _:
            return false
```

Adding a case breaks matches without a wildcard; a wildcard absorbs it. Return completeness follows the [function return rules](../functions/declarations-and-calls.md#unit-and-never).

## Optional and result values

[Optional](../types/optionals.md) and [Result](../errors/results.md) are alternatives, but do not match them. Use `if let value = expression:` for a value or success, `get(default)` for a default, `try` to propagate an error, and `is_error()` with `err()` to read a cause.

## Contract type patterns

A contract view keeps its concrete receiver. `ConcreteType(receiver)` recovers it for a particular implementation, and `_:` handles the rest. This is not a constructor call.

```text
import JsonError from "@std/json.ms"

fn describe(cause: Error) String:
    match cause:
        JsonError(json): return describe_json(json)
        _:
            return cause.message()

fn describe_json(cause: JsonError) String:
    match cause:
        InvalidInput: return "Invalid JSON limits"
        InvalidData: return "Malformed JSON"
        LimitExceeded: return "JSON limit exceeded"
```

- The type is a local or imported nominal record or alternative with an explicit implementation of the scrutinee's exact contract.
- Give exactly one receiver name or `_`, even for a payloadless alternative. The binding has the concrete type. Native opaque receivers fall to the wildcard.
- Generic patterns name the full application: `MyError[Int](cause)` differs from `MyError[String]`; an in-scope parameter may be an argument (`MyError[T](cause)`). The first arm matching the exact runtime type wins; duplicate patterns are rejected. A pattern cannot name another contract, a bare type parameter, or a single alternative case.
- A final wildcard is required because contracts are open. It binds nothing; use the original value for generic handling.
- The receiver is not copied, and matching adds no cleanup and catches no faults or cancellation. See [contract views](../types/contracts.md#explicit-contract-views).

## Matching resource references

Matching binds payload values and references without consuming them or registering cleanup. [Destructuring](../types/destructuring.md) uses brackets or braces; match cases use `Case(payload)`. See [references](../types/references.md).
