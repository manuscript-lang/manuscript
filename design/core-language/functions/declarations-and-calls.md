+++
title = "Declarations and calls"
weight = 21
+++

# Declarations and calls

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A function names its inputs, declares their types, and declares the type it returns. Its body runs in source order. Use `return` to send a value back to the caller.

```text
fn decrement(value: Int) -> Int:
    return value - 1

let remaining = decrement(value: 3)
```

Function parameters and return types are explicit; local annotations are optional. The caller can infer `remaining` as `Int` from the function's declared return type.

## Declarations and resolution

Named functions are module declarations or operations inside an `impl`. Nested named function declarations are rejected; use an anonymous function bound to a local instead. Every parameter has a unique name and an explicit type, and every function has an explicit result type, including `Unit`.

The compiler collects module declaration names and signatures before checking bodies. A function can call a later declaration, and ordinary and mutual function recursion are allowed. Duplicate module names and overloaded declarations are rejected. Generic function declarations and applications follow [generics](../types/generics.md).

Parameters belong to the function body's lexical scope. A local declaration cannot reuse a parameter's name in that same scope. Each branch, match arm, and loop body creates a nested scope; nested scopes may shadow an outer name.

## Argument names

Every supplied function argument must use `name: value`, including calls with a single argument. The name identifies the declared parameter. An unnamed argument is a compile error.

```text
fn reduce(amount: Int, deduction: Int) -> Int:
    return amount - deduction

let remaining = reduce(amount: 10, deduction: 3)
```

The rule applies to ordinary functions, methods, function values, and concurrency library APIs. Constructors name their fields, including `some(value: ...)`, `ok(value: ...)`, and `error(cause: ...)`. A call with no supplied arguments uses `()`.

`parallel` receives an ordered pack of zero-argument functions through `tasks: [first, second]`, with options such as `timeout: 2.seconds` supplied by name. Its heterogeneous results are specified in [parallel operations](../../concurrency/parallel.md).

Match payload bindings such as `some(value):` are patterns, rather than calls; see [pattern matching](../control-flow/pattern-matching.md).

Source declarations cannot define default or optional parameters, positional arguments, variadic parameters, or argument spreading. An `Optional[T]` source parameter is still required: callers explicitly supply `none` when absent. Existing trusted library API contracts may explicitly permit omitted named arguments; that permission does not follow from an `Optional` value type. Unknown, duplicate, and missing required argument names are compile errors. Supplied values must be compatible with the declared parameter types under [type compatibility](../types/compatibility.md); labels do not authorize numeric or contract conversions.

## Collections as arguments

To accept a variable number of values, declare an ordinary list parameter:

```text
fn sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value

    return total

let total = sum(values: [1, 2, 3])
let empty = sum(values: [])
```

The named argument supplies one immutable list. An existing `List[Int]` can be passed as `sum(values: existing_values)`. The parameter is required even for an empty list. Function values use the ordinary type `fn(values: List[Int]) -> Int`, and multiple list parameters need no additional call syntax.

See [collections](../types/collections.md) for list literals and element requirements.

## Evaluation order

Execution and argument evaluation follow source order. When arguments contain calls, those calls run in the order written before the outer function receives their results. Named arguments do not reorder execution to match the parameter declaration.

Evaluate the callable expression, including a method receiver, once before its arguments. Then evaluate argument expressions from left to right in their written order. Arrange the resulting values into declaration order only after evaluation. A failed or nonreturning expression prevents all later arguments and the outer invocation from running. Constructor fields follow the same rule.

This also matters for [concurrency APIs](../../concurrency/parallel.md#preparation): argument preparation and closure creation happen in the caller before any operation starts.

## Unit and Never

`unit` is the single value of `Unit`. A `Unit` function may use `return`, `return unit`, or fall through the end of its body. Other functions must return a compatible value on every reachable normal exit; bare `return` and reachable fallthrough are compile errors. There is no implicit return of a block's final expression.

```text
import panic from "@std/faults.ms"

fn check_positive(value: Int) -> Unit:
    if not (value > 0):
        return panic(message: "check failed")

fn missing_value() -> Int:
    return panic(message: "Required value is missing")
```

`panic` has type `fn(message: String) -> Never`. `Never` has no values: a `Never` expression cannot complete normally and is accepted where any value type is expected. This expression rule does not make `List[Never]` compatible with `List[Int]` or change function-type identity.

Return completeness uses a conservative control-flow check:

| Construct | Reachable normal exits |
| --- | --- |
| `return` or evaluation of Never | None |
| `if` without `else` | Branch exits plus a path past the statement |
| `if` with `else` or exhaustive `match` | The combined exits of all branches or arms |
| `for` or `while` with a condition other than literal `true` | A possible exit, because the body may not execute |
| Literal `while true` | Only a reachable `break` targeting that loop |

A nested function's return or nested loop's break cannot exit the enclosing function or loop. The check uses no additional constant folding.

Expression evaluation also has no normal successor when a necessarily evaluated subexpression cannot complete. This includes callable/receiver preparation, arguments, constructor fields, list elements, interpolation expressions, unary operands, and both operands of a non-short-circuit operator. A right-hand operand of `and` or `or` alone does not remove the possible exit, because it may be skipped; their left operand is always required. Creating a function value does not execute its body.

Track evaluation separately from result typing: `1 + panic(message: "stop")` has type `Int` under the [operator rules](../basics/expressions.md#never-operands), but cannot complete normally. A failed initializer accordingly prevents the following statement from being reachable.

```text
fn incomplete(active: Bool) -> Int:
    if active:
        return 1
    # Rejected: the false path reaches the end without returning Int.
```

Unreachable statements remain subject to parsing, name resolution, and type checking, but do not add reachable exits. A `Never` function must have no reachable normal return or fallthrough. A bare call may be used as a statement and its result discarded; non-call expressions cannot be standalone statements.

## Calls that suspend

A potentially blocking library call suspends the current lightweight task. It does not implicitly start another task. There are no `async` declarations or `await` annotations.

Manuscript has one function kind. Sequential code remains sequential when a library operation suspends; explicit concurrent execution is specified in [concurrency](../../concurrency/_index.md).

For functions used as data and the rules for captured values, continue with [function values and closures](function-values-and-closures.md).

[Previous: Type compatibility and expected types](../types/compatibility.md) · [Next: Function values and closures](function-values-and-closures.md)
