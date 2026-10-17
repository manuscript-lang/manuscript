+++
title = "Core-language conformance fixtures"
weight = 102
+++

# Core-language conformance fixtures

These fixtures check whether the compiler accepts or rejects core-language programs and whether executed expressions behave as specified. They complement the [semantic test plan](semantic-tests.md). Host behavior, resource lifetimes, and concurrency have separate fixtures.

Each accepted fixture (the file named under its heading) is an independent `.ms` module, with its application types and helper functions included. Its module-level `test` body has the ordinary `Unit` return contract. A rejected variant replaces or removes exactly the indicated text in that fixture, leaving the rest unchanged. If a variant introduces a standard declaration, add its individual import unless missing-import rejection is the behavior under test. Test each variant independently: combining unrelated errors makes the expected diagnostic ambiguous.

The expected stage identifies the violated contract: **parse** for invalid source structure; **resolution** for an unknown or ambiguous symbol; **type** for incompatible types, shapes, labels, bounds, or control flow after parsing and resolution. A checker may combine its resolution and type passes, but must identify the specified cause at the offending source span. Diagnostic wording and internal pass layout are implementation choices. Accepted fixtures must satisfy the stated checks, rather than merely generate Go that compiles.

## CL-01: Layout and named-call syntax

Contract: [source syntax](../../../core-language/basics/syntax.md) and [declarations and calls](../../../core-language/functions/declarations-and-calls.md).

Fixture: `tests/e2e/testdata/accept/cl-01.ms`.

This accepts trailing commas and multiline calls while mapping labels to declared parameters. Reordering the written labels does not change the parameter mapping.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the call with `subtract(amount: 9, deduction: 2)` | Accept; `remaining` is `Int` and equals 7 |
| Replace it with `subtract(9, 2)` | Accepted: positional arguments supply parameters in declaration order |
| Replace it with `subtract(amount: 9, amount: 2)` | Type rejection: duplicate supplied argument and missing `deduction` |
| Replace it with `subtract(amount: 9)` | Type rejection: missing required `deduction` |
| Replace it with `subtract(amount: 9, discount: 2)` | Type rejection: unknown argument name `discount` |
| Replace `return amount - deduction` with `return missing` | Resolution rejection: unknown binding `missing` |
| Remove the indentation before the function's `return` | Parse rejection: missing function block/module-level return |

Add lexical rejection fixtures for tabs, inconsistent dedentation, and unterminated delimiters as specified by the syntax chapter. Preserve the error's actual cause rather than reporting a later missing return.

## CL-02: Arithmetic grouping and Boolean short-circuiting

Contract: [expressions and operators](../../../core-language/basics/expressions.md) and [numeric operations](../../../core-language/basics/numbers-and-booleans.md).

Fixture: `tests/e2e/testdata/accept/cl-02.ms`.

Both short-circuit checks must complete without invoking the invalid division. This observes control flow, not only operator result types.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `2 + 3 * 4` with `2 + 3.0 * 4.0` | Type rejection: mixed `Int` and `Float`, without implicit conversion |
| Replace `true or invalid_division(zero: 0)` with `1 or invalid_division(zero: 0)` | Type rejection: logical operand must be `Bool` |
| Replace a comparison with `1 < 2 < 3` | Parse rejection: comparison operators cannot chain |
| Replace `true or invalid_division(zero: 0)` with `true or panic(message: "skipped")` | Accept and evaluate to true: the skipped Never operand is admissible as Bool |
| Replace `false and invalid_division(zero: 0)` with `false and panic(message: "skipped")` | Accept and evaluate to false: the right Never operand is not evaluated |

Integer overflow and division-by-zero fixtures must expect programming faults even if the backend could evaluate a wrapping Go operation. Use parameterized helpers to exercise runtime inputs rather than relying only on constant folding. Literal-range rejection is a separate compile-time fixture.

## CL-03: Nominal constructors and record bindings

Contract: [records](../../../core-language/types/records.md) and [destructuring](../../../core-language/types/destructuring.md).

```manuscript
import panic from "@std/faults.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) -> String:
    let {id: {value}, name: display_name} = customer
    return "{value}: {display_name}"

test "nominal record and nested binding":
    let customer = Customer(id: CustomerId("c1"), name: "Ada")
    if not (customer_name(customer: customer) == "c1: Ada"):
        return panic(message: "check failed")
```

| Independent variant | Expected outcome |
| --- | --- |
| Use `OrderId(value: "c1")` for the customer's `id` | Type rejection: nominal `OrderId` is not `CustomerId` |
| Omit `name` in `Customer(...)` | Type rejection: missing field |
| Add `active: true` to `Customer(...)` | Type rejection: unknown field |
| Supply `name` twice | Type rejection: duplicate field |
| Bind `{email}` from `customer` | Type rejection: unknown record field |
| Bind `{id: value, name: value}` | Type rejection: duplicate local binding |
| Assign `customer.name = "Grace"` after construction | Parse rejection: assignment accepts a binding name, not a field target |

Public-surface rejection fixture:

```manuscript

type PrivateId:
    value: String

export type PublicRecord:
    ids: List[PrivateId]
```

Reject at type checking: the exported field exposes the internal nominal `PrivateId` through a nested application. Changing `type PrivateId` to `export type PrivateId` accepts the module. Public closure is not satisfied merely because the outer standard `List` type is public.

## CL-04: Positional bindings and list shape

Contract: [collections](../../../core-language/types/collections.md) and [destructuring](../../../core-language/types/destructuring.md).

Fixture: `tests/e2e/testdata/accept/cl-04.ms`.

The empty literal gets its type from the annotation. `difference`'s binding is checked against `List[Int]`; its exact length is validated when the function runs.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `[9, 4]` with `[9, 4.0]` | Type rejection: heterogeneous numeric list without explicit conversion |
| Replace `let empty: List[Int] = []` with `let empty = []` | Type rejection: insufficient element-type information |
| Replace the binding with `let (first, second) = values` | Parse rejection: parenthesized positional binding is unsupported |
| Replace the test call with `difference(values: [9])` | Function accepts `List[Int]`; evaluation faults at dynamic destructuring |
| Replace the empty declaration with `let [only] = [1, 2]` | Type rejection: statically known length mismatch; no extra value is discarded |
| Annotate `let [first, second]: List[Int] = values` | Parse rejection: only simple name bindings accept annotations |

A literal-length mismatch in the binding itself is a compile-time shape error; a list parameter's runtime length is a programming-fault check. Optional optimization must not turn acceptance of the parameterized function into an invented fixed-length parameter type.

## CL-05: Function values retain parameter labels

Contract: [function values](../../../core-language/functions/function-values-and-closures.md).

Fixture: `tests/e2e/testdata/accept/cl-05.ms`.

| Independent variant | Expected outcome |
| --- | --- |
| Rename only `increase`'s parameter and body binding to `item` | Type rejection: `fn(item: Int) -> Int` is incompatible with `fn(value: Int) -> Int` |
| Call `transform(item: value)` in `apply` | Type rejection: unknown function-value argument label |
| Change `increase` to return `Float` with body `return 1.0` | Type rejection at assignment/call: function result contract differs |
| Change it to return `Never` with body `panic(message: "stop")` | Type rejection at assignment: `Never` expression compatibility does not make function result types covariant |
| Change the `apply` call to omit `transform` | Type rejection: required function argument is missing |

## CL-06: Return completeness and Boolean conditions

Contract: [declarations and calls](../../../core-language/functions/declarations-and-calls.md), [conditionals](../../../core-language/control-flow/conditionals.md), and [faults](../../../core-language/errors/faults.md).

Fixture: `tests/e2e/testdata/accept/cl-06.ms`.

The faulting branch has no normal successor. `discard` accepts normal fallthrough because it returns `Unit`.

| Independent variant | Expected outcome |
| --- | --- |
| Remove the `else` branch in `positive` | Type rejection: a reachable path falls through a non-`Unit` function |
| Replace `if value > 0` with `if value` | Type rejection: condition must be `Bool` |
| Replace `return value` with `return true` | Type rejection: returned value is not `Int` |
| Replace `discard`'s body with `return 1` | Type rejection: `Int` result in a `Unit` function |
| Replace it with `return` or `return unit` | Accept: explicit Unit return, like fallthrough |

Unreachable statements must still parse, resolve, and type-check; they do not repair a missing return on a reachable path.

## CL-07: Alternatives, positional payload patterns, and exhaustiveness

Contract: [alternatives](../../../core-language/types/alternatives.md) and [pattern matching](../../../core-language/control-flow/pattern-matching.md).

Fixture: `tests/e2e/testdata/accept/cl-07.ms`.

Constructors name payload fields; payload patterns bind positions in declaration order. Matching has no fallthrough.

| Independent variant | Expected outcome |
| --- | --- |
| Remove `Failed` arm | Type rejection: non-exhaustive match |
| Add another `Ready(other)` arm | Type rejection: duplicate/unreachable arm |
| Replace `Ready(value)` with `Ready(value, extra)` | Type rejection: payload arity mismatch |
| Replace `Ready(value)` with `Ready(value: local)` | Parse rejection: payload patterns are positional, not named-call syntax |
| Use `Outcome.Ready(amount: 8)` in the constructor | Type rejection: wrong payload field name |
| Add a final `_:` arm instead of `Failed` | Accept; wildcard covers the remaining case |
| Add `_:` with body `return 0` after both existing arms | Type rejection: every case is already covered, so the wildcard is unreachable |

Add ambiguity fixtures with two visible alternative types declaring `Ready`: unqualified construction must be rejected at resolution even when an expected result type could identify one; qualified construction succeeds. Match-case lookup is governed by the scrutinee type.

## CL-08: Iteration and nearest-loop control flow

Contract: [loops](../../../core-language/control-flow/loops.md).

```manuscript
import panic from "@std/faults.ms"


fn selected_sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        if value == 0:
            continue
        if value < 0:
            break
        total = total + value
    return total

test "iteration control":
    if not (selected_sum(values: [2, 0, 3, -1, 9]) == 5):
        return panic(message: "check failed")
    if not (selected_sum(values: []) == 0):
        return panic(message: "check failed")
```

| Independent variant | Expected outcome |
| --- | --- |
| Replace the iterable `values` with `3` | Type rejection: `Int` is not an admitted iterable |
| Assign `value = 4` in the loop body | Type rejection: iteration binding is immutable |
| Put `break` in the test body outside a loop | Type rejection: no enclosing loop |
| Put `continue` inside a nested anonymous function without its own loop | Type rejection: loop control cannot cross a function boundary |

For nested loops, verify that `break` and `continue` select the nearest enclosing loop. For `while`, verify that the condition is reevaluated and must have type `Bool`.

## CL-09: Generic declaration, inference, and bounds

Contract: [generics](../../../core-language/types/generics.md) and [equality](../../../core-language/types/equality-and-hashing.md).

Fixture: `tests/e2e/testdata/accept/cl-09.ms`.

Inference uses independently typed supplied arguments and known expected results. Explicit and inferred applications must select the same substitution. Generic bodies are checked against declared bounds, not only the concrete types used by these tests.

| Independent variant | Expected outcome |
| --- | --- |
| Use `Box[Int, String](value: 6)` | Type rejection: generic arity mismatch |
| Use `Box[String](value: 6)` | Type rejection: field is not the substituted `String` type |
| Use `unwrap[String](box: box)` | Type rejection: invariant `Box[Int]` is not `Box[String]` |
| Use `same(left: 6, right: 6.0)` | Type rejection: supplied types do not yield one exact `T` |
| Remove `Equal` from `same`'s bound | Type rejection in generic body: `T` does not establish equality |
| Use the undeclared type parameter `U` in `Box`'s field | Resolution rejection: unknown type `U` |

Separate fixture:

```manuscript
fn absent[T]() -> Optional[T]:
    return none

test "result context infers function arguments":
    let value: Optional[Int] = absent()
```

Accept both `absent()` and `absent[Int]()` with this annotation. Removing the annotation from `let value = absent()` is a type rejection because no evidence determines `T`. An explicit `absent[String]()` remains a type rejection at an `Optional[Int]` boundary; context cannot override specialization.

Intrinsic-name rejection fixture:

```manuscript
type Box[Int]:
    value: Int
```

Reject at resolution: a type parameter cannot redefine the intrinsic `Int` identity. `Int` is a resolved name rather than a lexical keyword, so this is not a grammar rejection. Apply the same namespace check to module declarations/imports and fixed compiler-bound names, without prohibiting ordinary local shadowing where the module rules permit it.

## CL-10: Explicit implementations and contract conversion

Contract: [operation contracts](../../../core-language/types/contracts.md).

Fixture: `tests/e2e/testdata/accept/cl-10.ms`.

`self` is implicit in the implementation body, never a source call argument. Conversion retains the concrete value; applying the same view constructor to an existing exact contract value is an identity conversion. The contract cannot be constructed without a value providing its declared implementation or already having that exact contract type.

| Independent variant | Expected outcome |
| --- | --- |
| Pass `offset` directly as `operation` | Type rejection: conversion to the contract must be explicit |
| Remove the `impl` declaration | Type rejection at conversion: `Offset` does not implement `Increment` |
| Rename implementation parameter/body binding from `value` to `item` | Type rejection: operation labels do not match the contract |
| Change implementation result/body to `Float`/`return 1.0` | Type rejection: result signature mismatch |
| Add `self: Offset` to the implementation parameter list | Parse rejection: reserved `self` cannot be declared as a parameter |
| Repeat the same `impl Increment for Offset` declaration | Type rejection: duplicate implementation |
| Replace `Increment(value: offset)` with `Increment()` | Type rejection: conversion requires the concrete `value` argument |

Accept local extensions for imported source records and alternatives. Exercise two modules implementing the same imported type/interface pair differently: local calls, returned contract views, bound methods, generic specialization and forwarding, and cleanup must preserve each selection. Reject method calls, view construction, generic bounds, and cleanup that rely on another module's extension, even when that module is imported. Reject overlap with a defining-module implementation or another extension in the same module. Path/import mechanics follow [module conformance](semantic-tests.md). Contract method ambiguity on a concrete value is resolved by explicit conversion to the selected contract.

## CL-10a: Generic implementations and nonoverlap

Contract: [generic implementations](../../../core-language/types/contracts.md#generic-implementations).

Fixture: `tests/e2e/testdata/accept/cl-10a.ms`.

The first block needs no bound to read and return its field. The second inherits `Equal` from the `SameValue` interface to compare it. `compare` proves that implementation's availability while checking its generic body, without waiting for a concrete instantiation.

| Independent variant | Expected outcome |
| --- | --- |
| Add a concrete `impl ReadValue[Int] for Box[Int]` supplying `get() -> Int` | Type rejection at declaration: overlap with the generic block, even if the body is identical |
| Add another `impl ReadValue[T] for Box[T]` supplying `get() -> T` | Type rejection at declaration: bounds cannot distinguish overlapping blocks |
| Replace the first block's `ReadValue[T]` with `ReadValue[Int]` | Type rejection at declaration: `get() -> T` does not match the substituted contract result `Int` |
| Remove `Equal` from `SameValue`'s interface parameters | Type rejection at declaration: unconstrained field values cannot be compared |
| Remove `Equal` from `compare`'s parameters | Type rejection in the generic function body: the implementation's bound is not proved |
| Replace the first block's receiver `Box[T]` with bare `T` | Type rejection at declaration: receiver must have a defining nominal data declaration |
| Add `[U]` to an implementation method | Parse rejection: methods cannot introduce their own parameters |

Also accept disjoint concrete implementations for different receiver applications when no generic block covers them, and two different contract applications for one receiver. For the latter, use explicit views to disambiguate equal operation names. Reject expanding recursive implementation specialization under the ordinary finite-application check. The implementation visibility rules apply equally to concrete and generic blocks. Test inherited receiver bounds whose interface names are absent or shadowed in the extending module, and nested generic receivers whose arguments rely on local implementations.

## CL-10b: Contract views and callbacks

Contract: [contract views](../../../core-language/types/contracts.md#explicit-contract-views) and sharing.

Fixture: `tests/e2e/testdata/accept/cl-10b.ms`.

All view helpers and function-bearing records in this fixture may be shared. Accept ordinary contract views in lists, optionals, fields, and concurrent callbacks; accept generic forwarding and returned functions. View construction evaluates its receiver once and neither copies nor closes native state. Reject mismatched contract applications, implicit concrete-to-contract conversions, function equality, and value-type intersection syntax.

## CL-11: Recursive records require collection indirection

Contract: [records](../../../core-language/types/records.md) and [generics](../../../core-language/types/generics.md).

Fixture: `tests/e2e/testdata/accept/cl-11.ms`.

Accept: recursive applications preserve `T` unchanged. Direct recursive fields and alternative payloads are also supported.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the `children` field type with `Tree[T]` | Declaration accepted; the shown `[]` constructor argument must be replaced by an initialized `Tree[T]` |
| Replace it with `Optional[Tree[T]]` | Declaration accepted; use `none` for a leaf and `some(child)` for a successor |
| Replace it with `Result[Tree[T], String]` | Declaration accepted; use an appropriate `ok(child)` or `error(message)` payload |
| Replace it with `List[Tree[List[T]]]` | Type rejection at declaration: recursive application expands the type parameter |

Check declaration-only variants separately from construction so argument errors do not obscure recursive type acceptance. Mutual recursive records and alternatives follow the same finite-application rule. Expanding cycles must fail even through function or interface signatures; import cycles remain a separate module rejection. Native fixtures exercise direct trees, cyclic equality, shallow clones, and explicit recursive key identity.

## CL-12: Collection iteration has concrete element types

Contract: [loops](../../../core-language/control-flow/loops.md) and [collections](../../../core-language/types/collections.md).

Fixture: `tests/e2e/testdata/accept/cl-12.ms`.

Accept these functions with the [collection operations](../../../core-language/types/collections.md#lookup-and-updates). The map loop element is `MapEntry[String, Int]`, whose record fields are `key: String` and `value: Int`; the set loop element is `Int`.

| Independent variant | Expected outcome |
| --- | --- |
| Replace map-loop `entry` with `[key, value]` | Parse rejection: a loop introduces one identifier, not a destructuring pattern |
| Bind `{missing}` from `entry` | Type rejection: unknown map-entry record field |
| Declare `let label: Int = key` | Type rejection: map key is `String`, not `Int` |
| Replace `Set[Int]` with `Set[Float]` | Type rejection: `Float` is not `Hashable` |
| Replace `Map[String, Int]` with `Map[List[Int], Int]` | Type rejection: collections are not hashable keys |

Runtime collection fixtures use the minimum constructor/update API: verify insertion-order traversal for maps and sets, and evaluate an effectful iterable expression exactly once. The concrete expectations are in [runtime bindings](runtime-bindings.md).

## CL-13: Lexical text forms and declaration-only modules

Contract: [source grammar](../../../core-language/basics/grammar.md) and [text](../../../core-language/basics/text-and-bytes.md).

Fixture: `tests/e2e/testdata/accept/cl-13.ms`.

Escaped braces are literal text; unescaped braces select interpolation. Source UTF-8 encoding and Unicode scalar validation are part of parsing text, independent of later text-conversion APIs.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the scalar escape with `"\u{D800}"` | Parse rejection: surrogate is not a Unicode scalar |
| Replace it with `"\u{110000}"` | Parse rejection: scalar exceeds the Unicode range |
| Replace an escape with `"\q"` | Parse rejection: unknown escape |
| Replace `echo`'s function name with the reserved word `if` | Parse rejection: reserved word is not an identifier |
| Add module-level `var extra = 1` after the test | Parse rejection: executable bindings belong in a block |
| Add module-level `let extra = helper()` after the test | Type rejection: a constant takes literals, operators, collections, and other constants |
| Replace `let no_value: Unit = unit` with `let no_value: Unit = 0` | Type rejection: `Int` is not `Unit` |
| Replace it with `let smallest: Int = -9223372036854775808` | Accept: directly negated minimum Int literal |
| Replace it with `let too_large = 9223372036854775808` | Type rejection: positive literal is outside Int range |
| Replace it with `let too_large = 1e400` | Type rejection: Float literal would round to infinity |
| Replace it with `let unknown = 01` | Parse rejection: leading-zero numeric spelling is not supported |

Equivalent LF and CRLF encodings must produce the same parsed structure after documented newline normalization. Invalid UTF-8 input must be rejected rather than silently replaced. Blank/comment-only lines do not introduce suites, and comment markers within text remain text.

### Universal string conversion

Every value supports `toString()` and direct interpolation, including unconstrained generic parameters. The [executable conversion fixture](https://github.com/manuscript-lang/manuscript/blob/main/tests/e2e/testdata/accept/to-string.ms) exercises scalar formatting, nested records and collections, alternatives, interface views, bound methods, functions, and closed native resources. It checks that receivers evaluate once and interpolation evaluates left to right. Exact representations are defined in [Strings and bytes](../../../core-language/basics/text-and-bytes.md#deterministic-formatting).

| Independent variant | Expected outcome |
| --- | --- |
| Call `true.toString(value: 1)` | Type rejection: `toString` takes no arguments |
| Bind `value.toString` to `fn() -> Int` | Type rejection: the method returns String |
| Pass a record to a String parameter without calling `.toString()` | Type rejection: conversion remains explicit at call boundaries |

## CL-14: Result propagation preserves the declared error type

Contract: [Result](../../../core-language/errors/results.md) and [try propagation](../../../core-language/errors/propagation.md).

Fixture: `tests/e2e/testdata/accept/cl-14.ms`.

Successful construction obtains the complete `Result[Int, Problem]` type from the declared return contract. Propagation leaves the remaining body unexecuted on an expected error; it does not introduce an implicit error union or conversion.

| Independent variant | Expected outcome |
| --- | --- |
| Change only `doubled`'s declared error type to `OtherProblem` | Type rejection at `try`: incompatible propagated error |
| Change `doubled` to return `Int`, and its final return to `return accepted * 2` | Type rejection at `try`: enclosing function must return compatible `Result` |
| Replace `ok(value: value)` with `ok(value: true)` | Type rejection: wrong successful payload type |
| Replace the error payload with `OtherProblem.Invalid(reason: "negative")` | Type rejection: wrong declared error payload type |
| Replace the `try` operand with `value` | Type rejection: operand is not `Result` |
| Replace the local binding with `let accepted: Int = try ok(value: 3)` | Type rejection: annotation does not propagate through `try` to infer the missing error type |
| Replace the local binding with `let accepted = try Result[Int, Problem].ok(value: value)` | Accept: qualification establishes both Result arguments before propagation |

An anonymous function establishes its own propagation boundary. Test that an inner `Unit` closure cannot use `try` merely because its enclosing function returns `Result`; the inner function's signature controls compatibility.

## CL-15: Equality eligibility does not imply hashing eligibility

Contract: [equality and hashing](../../../core-language/types/equality-and-hashing.md).

Fixture: `tests/e2e/testdata/accept/cl-15.ms`.

Optional equality compares its tag and eligible payload. Decimal equality compares numeric values despite different trailing zeroes. List equality observes positions rather than treating a list as a set. Eligibility is checked recursively on record fields.

| Independent variant | Expected outcome |
| --- | --- |
| Add `if callback == callback:` with a `return` body | Type rejection: a function field makes `Callback` ineligible for equality |
| Add `if increment == increment:` with a `return` body | Type rejection: function values have no equality |
| Use `preserve_key(value: [1, 2])` | Type rejection: equal lists are not hashable |
| Use `preserve_key(value: 1.0)` | Type rejection: `Float` is equal-comparable but not hashable |
| Declare `let wrong: Optional[Float] = present` | Type rejection: invariant optional applications differ |

Test generated record/alternative equality with eligible scalar leaves and reject derivations containing a noneligible leaf. Do not treat safe concurrent access, identical object references, or a user-written marker implementation as evidence of equality.

## CL-16: Expected data types supply constructor context

Contract: [compatibility and expected types](../../../core-language/types/compatibility.md), [Optional](../../../core-language/types/optionals.md), and [Result](../../../core-language/errors/results.md).

```manuscript
import panic from "@std/faults.ms"


type Input:
    names: List[Optional[String]]

fn outcome_value(outcome: Result[Int, String]) -> Int:
    match outcome:
        ok(value):
            return value
        error(_):
            return -1

test "data constructor context":
    let input = Input([none, some("Ada")])
    let success: Result[Int, String] = ok(3)
    let failure: Result[Int, String] = error("unavailable")
    let absent: Optional[Int] = none
    let nested: List[List[Int]] = [[], [1]]
    if not (outcome_value(outcome: success) == 3):
        return panic(message: "check failed")
    if not (outcome_value(outcome: failure) == -1):
        return panic(message: "check failed")
```

The field, binding annotation, or substituted parameter determines missing data arguments; it does not convert an independently known incompatible type. Forward declarations and contextual list elements do not require module-level execution.

| Independent variant | Expected outcome |
| --- | --- |
| Remove `: Result[Int, String]` from `success` | Type rejection: `ok`'s payload does not determine the error type |
| Remove it from `failure` | Type rejection: `error`'s payload does not determine the success type |
| Remove `: Optional[Int]` from `absent` | Type rejection: `none` supplies no payload type |
| Change `some(value: "Ada")` to `some(value: 3)` | Type rejection: independently known payload conflicts with expected `String` |
| Replace `none` for `absent` with `3` | Type rejection: no implicit Optional wrapping |
| Replace `ok(value: 3)` for `success` with `3` | Type rejection: no implicit Result wrapping |

Add a nonempty-list fixture `[none, some(value: 1)]`: the independently typed `some` determines `Optional[Int]` for the absent element. Reject `[some(value: 1), some(value: "one")]`; no implicit union is formed. CL-09 separately checks generic function inference from arguments and expected results, including rejection when neither determines a parameter.

## CL-17: Nonreturning subexpressions determine control-flow exits

Contract: [Unit and Never](../../../core-language/functions/declarations-and-calls.md#unit-and-never).

The following independent module is a type-checking fixture; its faulting functions are not invoked as passing tests.

Fixture: `tests/e2e/testdata/accept/cl-17.ms`.

Accept: the initializer and return expression cannot produce values; the literal-true loop has no reachable break and therefore no normal exit. An expected annotation does not make a `Never` expression return an `Int` at runtime.

| Independent variant | Expected outcome |
| --- | --- |
| Replace the initializer with `0` | Type rejection: the `Never` function now reaches normal fallthrough |
| Replace the binding with `let impossible: Int = 1 + panic(message: "stop")` | Accept: the operator result is Int, but its required right operand cannot return |
| Replace the binding with `let impossible: Bool = not panic(message: "stop")` | Accept: `not` selects Bool, but its required operand cannot return |
| Replace the binding with `let impossible: Int = panic(message: "left") + panic(message: "right")` | Type rejection: two Never operands supply no numeric candidate, even under an Int annotation |
| Replace the binding with `let impossible: Int = -panic(message: "stop")` | Type rejection: unary numeric selection requires an independently known numeric operand |
| Replace the binding with `let possible: Bool = false and panic(message: "skipped")` | Type rejection: the Never function has reachable fallthrough because the right operand is skipped |
| Replace the binding with `let possible: Bool = true or panic(message: "skipped")` | Type rejection: short circuiting permits normal fallthrough |
| Add `return unit` after its initializer | Type rejection: unreachable returns still must match the declared result type |
| Replace `return panic(...)` with bare `return` | Type rejection: a non-Unit function requires a value |
| Replace `while true` with `while not false` | Type rejection: nonliteral conditions retain a possible exit; no constant folding proves return completeness |
| Add a reachable `break` inside `endless` | Type rejection: the loop can exit and the `Int` function then falls through |

Extend the fixture with a nested loop whose own break does not exit the outer literal-true loop. A closure's return likewise does not return from its enclosing function. Nonreturning callable/argument evaluation prevents later arguments and the outer call from running, under the ordinary evaluation-order contract.

## CL-18: Suite-bodied function expressions resume the enclosing layout

Contract: [anonymous-function suites](../../../core-language/basics/grammar.md#anonymous-function-suites-inside-delimiters) and [function values](../../../core-language/functions/function-values-and-closures.md).

Fixture: `tests/e2e/testdata/accept/cl-18.ms`.

The unused closure's body must not run. Its dedent terminates both the function expression and the surrounding binding statement, so the next binding does not require an extra blank line. The grouped closure ends before the outer argument comma; the final ungrouped closure resumes the still-open call's continuation when its body dedents. The nested `if` dedents within the active function suite rather than ending the enclosing call.

| Independent variant | Expected outcome |
| --- | --- |
| Replace `dormant`'s function expression with `fn() -> Int: 1` | Parse rejection: a function body requires a statement suite |
| Indent the final call-closing `)` to the closure-body level | Parse rejection: a delimiter opened outside the function body cannot close at body indentation |
| Add `let after = 1` at the next test-body indentation without a blank line after `dormant` | Accept: synthetic statement boundary follows the function-expression suite |
| Replace the anonymous expression with a nested named `fn dormant() -> Int:` declaration | Parse rejection: named functions are not local statements |
