+++
title = "Declarations and calls"
weight = 1
+++

# Declarations and calls

A function names its inputs, declares their types, and declares the type it returns. Its body runs in source order. Use `return` to send a value back from a multiline body. A short expression body can stay on one line and return implicitly: `fn double(value: Int) -> Int: value * 2`. See the [suite rules](../basics/grammar.md#statements-and-patterns) for inline bodies.

```manuscript
fn decrement(value: Int) -> Int:
    return value - 1

let remaining = decrement(3)
```

Function parameters and return types are explicit; local annotations are optional. The caller can infer `remaining` as `Int` from the function's declared return type.

## Declarations and resolution

Named functions are module declarations or operations inside an `impl`. Nested named function declarations are rejected; use an anonymous function bound to a local instead. Every parameter has a unique name and an explicit type, and every function has an explicit result type, including `Unit`.

The compiler collects module declaration names and signatures before checking bodies. A function can call a later declaration, and ordinary and mutual function recursion are allowed. Duplicate module names and overloaded declarations are rejected. Generic function declarations and applications follow [generics](../types/generics.md).

Parameters belong to the function body's lexical scope. A local declaration cannot reuse a parameter's name in that same scope. Each branch, match arm, and loop body creates a nested scope; nested scopes may shadow an outer name.

## Argument names

Argument labels are optional. An unlabeled expression supplies the first parameter not filled by an earlier argument, in declaration order. An explicit `name: value` supplies that named parameter in any order.

For compatibility, a bare identifier matching a parameter name remains shorthand for `name: name` when the callable has multiple parameters. This selects the named parameter even when it is already filled, in which case the call is rejected as a duplicate. Parenthesizing an identifier makes it positional: `(name)` is an ordinary expression.

```manuscript
fn reduce(amount: Int, deduction: Int) -> Int:
    return amount - deduction

let remaining = reduce(10, 3)
let explicit_remaining = reduce(amount: 10, deduction: 3)
let mixed = reduce(deduction: 3, 10)
let amount = 10
let deduction = 3
let shorthand = reduce(deduction, amount)
```

All four results are `7`. Resolve each argument from left to right; labels do not reserve parameters for later arguments. For example, `reduce(10, amount: 3)` supplies `amount` twice and fails, while `reduce(amount: 10, 3)` supplies `deduction` positionally. Unknown labels do not fill a declared parameter. Once every parameter is filled, another positional argument is an error. Arguments never skip a parameter merely because it has a default.

The rule applies to ordinary and generic functions, methods, function values, library APIs, record and alternative-case constructors, and explicit contract views. A method's implicit receiver is evaluated before its arguments and does not consume a positional slot. Constructor slots follow field declaration order. A zero-parameter function uses `()`. Existing labeled calls and function matching-name shorthand retain their meaning. Function-type parameter names remain part of [type identity](function-values-and-closures.md); omitting invocation labels does not make differently named callback signatures compatible.

TaskGroup.start accepts one zero-argument function and infers a typed Task[T] handle. Task and group joins use ordinary receiver calls; see [task groups](../../concurrency/task-groups.md).

Match payload bindings such as `some(value):` are patterns, rather than calls; see [pattern matching](../control-flow/pattern-matching.md).

A parameter with a default may be omitted; every other parameter remains required. An `Optional[T]` parameter without a default is still required: callers explicitly supply `none` when absent. A supplied `T` is wrapped once as `some(value: ...)` for a standard `Optional[T]` parameter; see [optional arguments](../types/optionals.md#passing-optional-arguments). Variadic parameters and argument spreading are not supported. Existing trusted library API contracts may explicitly permit omitted arguments; that permission does not follow from an `Optional` value type. Unknown labels, duplicate arguments, missing required arguments, and excess positional arguments are compile errors. Supplied values must be compatible with the declared parameter types under [type compatibility](../types/compatibility.md); optional labels do not authorize numeric or contract conversions.

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

`usual` is `4` and `explicit` is `3`. A function whose sole parameter has a default also accepts `function()`. Defaults may appear before required parameters. To omit an earlier default and supply a later required parameter, use its label: `fn choose(first: Int = 1, second: Int) -> Int: second` accepts `choose(second: 2)`. Calling `choose(2)` supplies `first` and reports missing `second`.

A default is checked against its explicit parameter type in the function's lexical scope. It may use imports, module declarations, earlier parameters, and an implementation method's `self`. Current and later parameters are not yet in scope. Anonymous functions may use captured outer bindings in defaults; those bindings follow the ordinary snapshot and sharing rules.

Evaluate the callable and all supplied arguments first, in written order. Then evaluate omitted defaults once each in parameter declaration order, before entering the body. Defaults run afresh on each invocation; supplying a value skips its default entirely. Explicit `none`, `unit`, `false`, and zero are supplied values. A failing default prevents later defaults and the body from running. `try` in a default propagates from the called function under its declared result type.

Named functions, anonymous functions, and implementation methods with bodies may declare defaults. Function-type annotations and alternative payloads cannot. Application interface signatures only permit `= none` defaults on Optional parameters. Pinned standard declarations may also supply checked expressions, such as empty command input; these are prepared before native dispatch and inherited by source implementations of that standard interface. A concrete implementation's explicit parameter default takes precedence; an interface view uses the interface default. Record fields have their own [default expressions](../types/records.md#construction). A method default permits omission through its concrete receiver or inferred bound method value; calls through an interface view follow the interface's signature. Defaults do not provide generic inference: omitted arguments supply no type evidence, and a generic default must type-check under the declared bounds.

An inferred immutable local copy of a callable retains its defaults. Explicit function-type annotations, mutable bindings, function parameters and results, fields, and generic forwarding require the full argument list. Defaults are not part of function-type identity; a defaulted function can be passed wherever its complete labeled signature is expected.

## Collections as arguments

To accept a variable number of values, declare an ordinary list parameter:

```manuscript
fn sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value

    return total

let total = sum([1, 2, 3])
let empty = sum([])
```

The argument supplies one list reference. An existing `List[Int]` can be passed as `sum(existing_values)` or `sum(values: existing_values)`. The parameter is required even for an empty list. Function values use the ordinary type `fn(values: List[Int]) -> Int`, and functions with multiple list parameters follow the same optional-label rule.

See [collections](../types/collections.md) for list literals and element requirements.

## Evaluation order

Execution and argument evaluation follow source order. When arguments contain calls, those calls run in the order written before the outer function receives their results. Named arguments do not reorder execution to match the parameter declaration.

Evaluate the callable expression, including a method receiver, once before its arguments. Then evaluate supplied argument expressions from left to right in their written order. Arrange those values into declaration order after their evaluation, then evaluate omitted [defaults](#default-arguments) in the called function before its body. A failed or nonreturning supplied expression prevents all later arguments and the outer invocation from running. Constructor fields follow the same rule.

This also matters for [concurrency APIs](../../concurrency/task-groups.md#preparation): each callback is prepared in the caller before that operation starts; earlier group submissions may already be running.

## Unit and Never

`unit` is the single value of `Unit`. A `Unit` function may use `return`, `return unit`, or fall through the end of its body. Other functions must return a compatible value on every reachable normal exit; bare `return` and reachable fallthrough are compile errors. A single-line function expression body returns its value: `fn double(value: Int) -> Int: value * 2`. Multiline bodies require explicit `return`; their final expression is not an implicit return.

```manuscript
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

Expression evaluation also has no normal successor when a necessarily evaluated subexpression cannot complete. This includes callable/receiver preparation, arguments, constructor fields, list elements, map keys and values, interpolation expressions, unary operands, and both operands of a non-short-circuit operator. A right-hand operand of `and` or `or` alone does not remove the possible exit, because it may be skipped; their left operand is always required. Creating a function value does not execute its body.

Track evaluation separately from result typing: `1 + panic(message: "stop")` has type `Int` under the [operator rules](../basics/expressions.md#never-operands), but cannot complete normally. A failed initializer accordingly prevents the following statement from being reachable.

```manuscript
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
