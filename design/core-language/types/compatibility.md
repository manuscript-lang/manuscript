+++
title = "Type compatibility and expected types"
weight = 19
+++

# Type compatibility and expected types

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler uses the same compatibility rules for annotations, assignment, arguments, returns, constructor fields, and collection elements. An expression is assignable to an expected type when its type is exactly that type, except that an expression of `Never` is assignable wherever control cannot produce a value. This exception does not change function-type identity or allow return-type covariance.

## Exact and nominal identity

| Type form | Identity and compatibility |
| --- | --- |
| Built-in | Fixed compiler or standard identity |
| Record or alternative | Defining module, declaration, and ordered type arguments; matching fields or cases do not establish compatibility |
| Contract view | Nominal contract application, plus whether it is plain or shared; conversions are [explicit](contracts.md#explicit-contract-views) |
| Generic application | Exact declaration and every ordered argument; `List[Int]` and `List[Float]` are distinct |
| Function | Exact parameter labels, declaration order, parameter types, and result type; no variance or label/order adaptation |

Caller-written argument order affects evaluation without changing function identity. A generic bound grants properties, not subtyping. Shared/plain arguments remain distinct during inference; `List[Contract]` fails its element bound, while `List[Contract & Shareable]` may satisfy it.

Type positions use [ordinary name resolution](../../modules-and-capabilities/modules/declarations.md#names-and-declaration-order). A value shadowing a type name causes an error, not a second lookup in a hidden namespace. Unqualified cases follow [alternative lookup](alternatives.md#construction-and-identity); expected types cannot override a lexical binding or choose an ambiguous case.

`Shareable`, `Equal`, and `Hashable` are [compiler bounds](generics.md#bounds), not standalone value types. The only value-type refinement is `Contract & Shareable`; other intersections and refinements are rejected.

```text
fn identity(value: Int) -> Int:
    return value

let exact: fn(value: Int) -> Int = identity
# Rejected: amount differs from value.
let relabeled: fn(amount: Int) -> Int = identity
```

There are no implicit numeric conversions, optional wrapping/unwrapping, result wrapping, structural record conversions, unions, or nullable references. An integer literal has type `Int` even under an expected `Float`; use the [explicit conversion API](../../standard-library/data-and-io/operations.md#numeric-and-time-conversion). The type checker does not choose an arbitrary common type for incompatible values.

## Propagating context

An explicit local annotation, assignment target, declared return type, substituted parameter type, record field type, or alternative payload type supplies an expected type to its expression. Expected types propagate through parentheses and recursively into list elements and constructor fields/payloads. They supply missing type arguments for uniquely resolved data constructors such as `none`, `ok`, and `error`. They do not choose between globally ambiguous unqualified constructor names or change independently determined expression types.

```text
type Input:
    names: List[Optional[String]]

let input = Input(names: [none, some(value: "Ada")])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, String] = ok(value: 1)
let failure: Result[Int, String] = error(cause: "unavailable")
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(value: 1)
```

A context-dependent expression without enough information is rejected, rather than receiving a dynamic or implicit unknown type. Thus bare unannotated `none`, `[]`, and `ok(value: 1)` are incomplete; `some(value: 1)` completely determines `Optional[Int]`. For a nonempty list, independently typed elements can determine context for the remaining elements; `[none, some(value: 1)]` is `List[Optional[Int]]`. If independently typed elements disagree, the list is rejected.

Context flows through the constructors, literals, and parentheses listed above; it does not flow backward through operators or prefix `try`. Operator operands and a `try` operand must determine their own types before the enclosing expression is checked. In particular, an expected `Int` for `try` does not invent a `Result` error type from the enclosing function's error type.

```text
fn known() -> Result[Int, String]:
    let number: Int = try Result[Int, String].ok(value: 1)
    return ok(value: number)

fn unknown() -> Result[Int, String]:
    # Rejected: the try operand's error type is undetermined.
    let number: Int = try ok(value: 1)
    return ok(value: number)
```

Similarly, an expected `Bool` cannot make `[] == []` well typed; neither operand determines a list element type. Explicitly qualify or annotate operands when their types would otherwise be incomplete.

Never operands use the [operator candidate rules](../basics/expressions.md#never-operands). Those rules select a required operand type locally; they do not infer it backward from an expected result.

Generic function inference uses supplied argument types only, as specified in [generics](generics.md#inference-from-arguments). An expected return type does not infer missing function type arguments. A generic function value must be explicitly specialized before an expected function type can check it. Anonymous functions still require their own explicit parameter/result types.

## Validation boundaries

Every declaration's referenced types must resolve and every application must satisfy arity and bounds. Generic bodies are checked under declared bounds. Public signatures satisfy [public type visibility](records.md#public-data-surfaces), and recursive concrete layouts satisfy [guarded recursion](records.md#recursive-data). These checks precede lowering and do not rely on Go's structural interfaces or implicit assignments.

Runtime cancellation and resource closed-state errors do not alter static assignability. Their separate contracts remain governed by the existing runtime and reference chapters.

[Previous: Generics and bounds](generics.md) · [Next: Declarations and calls](../functions/declarations-and-calls.md)
