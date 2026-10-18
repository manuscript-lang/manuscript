+++
title = "Declarations and calls"
weight = 1
+++

# Declarations and calls

A function names its inputs, declares their types, and declares its return type. Use `return` in a multiline body. A one-line body returns its expression implicitly: `fn double(value: Int) -> Int: value * 2` (see [suite rules](../basics/grammar.md#statements-and-patterns)).

```manuscript
fn decrement(value: Int) -> Int:
    return value - 1

let remaining = decrement(3)
```

Parameters and return types are explicit; local annotations are optional.

## Declarations and resolution

- Named functions are module declarations or operations inside an `impl`. Nested named functions are rejected; bind an anonymous function to a local instead.
- Parameter names are unique and every parameter and result type is explicit, including `Unit`.
- Signatures are collected before bodies are checked, so functions may call later declarations and recurse, including mutually.
- Duplicate module names and overloads are rejected. Generics follow [generics](../types/generics.md).
- Parameters live in the body's scope; a local cannot reuse a parameter name there. Branches, arms, and loop bodies open nested scopes that may shadow outer names.

## Argument names

Labels are optional. An unlabeled argument fills the first parameter not yet filled, in declaration order. `name: value` fills that parameter in any order. A bare identifier is an ordinary expression, so renaming a local never changes which parameter it fills.

```manuscript
fn reduce(amount: Int, deduction: Int) -> Int:
    return amount - deduction

let remaining = reduce(10, 3)
let explicit_remaining = reduce(amount: 10, deduction: 3)
let mixed = reduce(deduction: 3, 10)
let amount = 10
let deduction = 3
let swapped = reduce(deduction: deduction, amount: amount)
```

All five results are `7`. Arguments resolve left to right and labels do not reserve parameters for later arguments:

- `reduce(10, amount: 3)` supplies `amount` twice and fails.
- `reduce(amount: 10, 3)` supplies `deduction` positionally.
- Unknown labels, duplicate or missing arguments, and excess positional arguments are compile errors.
- Arguments never skip a parameter because it has a default.
- Values must be compatible with the parameter types under [type compatibility](../types/compatibility.md); labels never authorize conversions.

`reduce(amount: amount, deduction: deduction)` binds the same as `reduce(amount, deduction)`. `ms fmt --drop-labels` removes `name: name` labels only when the call binds identically without them.

The rule covers functions, generics, methods, function values, library APIs, constructors, and explicit contract views. A method's receiver is evaluated before its arguments and takes no positional slot. Constructor slots follow field declaration order. A zero-parameter function uses `()`. Function-type parameter names remain part of [type identity](function-values-and-closures.md).

A parameter with a default may be omitted; others are required, including `Optional[T]` without a default (pass `none`). A supplied `T` is wrapped once as `some(value: ...)` ([optional arguments](../types/optionals.md#passing-optional-arguments)). Variadics and spreading are unsupported. Match bindings such as `some(value):` are [patterns](../control-flow/pattern-matching.md), not calls.

## Default arguments

Write `= expression` after a parameter's type to supply a default:

```manuscript
fn subtract(amount: Int, deduction: Int = 1) -> Int:
    return amount - deduction

fn example() -> Int:
    let usual = subtract(5)
    let explicit = subtract(5, 2)
    return usual + explicit
```

`usual` is `4` and `explicit` is `3`. A function whose sole parameter has a default also accepts `function()`.

- Defaults may precede required parameters; skip one by labeling a later argument. `fn choose(first: Int = 1, second: Int) -> Int: second` accepts `choose(second: 2)`, while `choose(2)` supplies `first` and misses `second`.
- A default is checked against its parameter type in the function's scope. It may use imports, module declarations, earlier parameters, and `self`; current and later parameters are not in scope. Anonymous functions may use captures.
- Evaluation: the callable and supplied arguments run first in written order, then omitted defaults run once each in declaration order, before the body. Defaults run afresh per call. `none`, `unit`, `false`, and zero are supplied values.
- A failing default stops later defaults and the body. `try` in a default propagates under the function's result type.
- Named functions, anonymous functions, and `impl` methods may declare defaults; function types and alternative payloads cannot. Interface signatures permit only `= none` on Optional parameters. A concrete default wins; an interface view uses the interface's.
- Record fields have their own [defaults](../types/records.md#construction). Omitted arguments give no generic type evidence.
- An inferred immutable local copy of a callable keeps its defaults. Annotated function types, mutable bindings, parameters, results, fields, and generic forwarding need the full argument list. Defaults are not part of function-type identity.
- Native standard-library slice: expression defaults work on nongeneric functions and ordinary record fields. Standard interface defaults must be closed literals. Native generic defaults, defaults on opaque native constructors, and recursive native default expansion are unsupported.

## Collections as arguments

To accept a variable number of values, declare an ordinary list parameter:

```manuscript
fn sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total += value

    return total

let total = sum([1, 2, 3])
let empty = sum([])
```

The argument is one list reference: `sum(existing_values)` or `sum(values: existing_values)`. The parameter is required even for an empty list.

See [collections](../types/collections.md) for list literals and element requirements.

## Evaluation order

Evaluation follows source order; named arguments never reorder it.

1. Evaluate the callable, including a method receiver, once.
2. Evaluate supplied arguments left to right.
3. Arrange values into declaration order, then evaluate omitted [defaults](#default-arguments) before the body.

A failed or nonreturning argument prevents later arguments and the call. Constructor fields follow the same rule. Concurrency callbacks are prepared in the caller before the operation starts.

## Unit and Never

`unit` is the single value of `Unit`. A `Unit` function may `return`, `return unit`, or fall off the end. Other functions must return a compatible value on every reachable exit; bare `return` and reachable fallthrough are errors. Multiline bodies need explicit `return`.

```manuscript
import panic from "@std/faults.ms"

fn check_positive(value: Int) -> Unit:
    if not (value > 0):
        return panic(message: "check failed")

fn missing_value() -> Int:
    return panic(message: "Required value is missing")
```

`panic` has type `fn(message: String) -> Never`. A `Never` expression cannot complete normally and is accepted where any value type is expected. `List[Never]` is not compatible with `List[Int]`.

Return completeness uses a conservative control-flow check:

| Construct | Reachable normal exits |
| --- | --- |
| `return` or evaluation of Never | None |
| `if` without `else` | Branch exits plus a path past the statement |
| `if` with `else` or exhaustive `match` | The combined exits of all branches or arms |
| `for` or `while` with a condition other than literal `true` | A possible exit, because the body may not execute |
| Literal `while true` | Only a reachable `break` targeting that loop |

A nested function's `return` or nested loop's `break` cannot exit the enclosing one. No further constant folding applies.

An expression has no normal successor when a necessarily evaluated subexpression cannot complete: callable or receiver, arguments, constructor fields, list elements, map entries, interpolations, unary operands, and both operands of non-short-circuit operators. The right operand of `and`/`or` may be skipped, so it does not count; the left always does. Creating a function value does not run its body.

Typing is separate: `1 + panic(message: "stop")` has type `Int` ([operators](../basics/expressions.md#never-operands)) but cannot complete, so the next statement is unreachable.

```manuscript
fn incomplete(active: Bool) -> Int:
    if active:
        return 1
    # Rejected: the false path reaches the end without returning Int.
```

Unreachable statements are still parsed, resolved, and type-checked. A `Never` function has no reachable normal exit. A bare call may be a statement; other expressions cannot.

## Calls that suspend

A blocking library call suspends the current lightweight task without starting another. There is no `async` or `await`; Manuscript has one function kind, and sequential code stays sequential.

See [function values and closures](function-values-and-closures.md) for functions as data.
