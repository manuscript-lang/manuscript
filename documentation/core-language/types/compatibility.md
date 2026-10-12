+++
title = "Type compatibility and expected types"
weight = 10
+++

# Type compatibility and expected types

The type you provide must match the type required at that position. This applies to variable annotations, assignments, arguments, returns, fields, and collection elements. For example, an `Int` cannot silently become a `Float`, and two records do not become interchangeable just because their fields match.

An expression of type `Never` cannot produce a value, so it can appear where any expression value is expected. Errors implementing the standard `Error` interface can also pass directly into an Error boundary; see [error compatibility](../errors/propagation.md#error-compatibility). These rules do not make differently declared function types interchangeable.

## Exact and nominal identity

| Type form | Identity and compatibility |
| --- | --- |
| Built-in | Fixed compiler or standard identity |
| Record or alternative | Defining module, declaration, and ordered type arguments; matching fields or cases do not establish compatibility |
| Contract view | Nominal contract application; conversions are [explicit](contracts.md#explicit-contract-views), except that an implementing error can pass directly into the standard Error boundary |
| Generic application | Exact declaration and every ordered argument; Result can widen its error to Error while retaining the same success type |
| Function | Exact parameter labels, declaration order, parameter types, and result type; no variance or label/order adaptation |

Caller-written argument order affects evaluation without changing function identity. A generic bound grants properties, not subtyping. Shared/plain arguments remain distinct during inference; `List[Contract]` fails its element bound, while `List[Contract]` may satisfy it.

Type positions use [ordinary name resolution](../modules/declarations.md#names-and-declaration-order). A value shadowing a type name causes an error, not a second lookup in a hidden namespace. Unqualified cases follow [alternative lookup](alternatives.md#construction-and-identity); expected types cannot override a lexical binding or choose an ambiguous case.

`Equal` and `Hashable` are [standard interfaces](equality-and-hashing.md) and can be used as bounds or explicit interface views. Value types have no intersection/refinement syntax; conjunction is available only for generic bounds.

```manuscript
fn identity(value: Int) -> Int:
    return value

let exact: fn(value: Int) -> Int = identity
# Rejected: amount differs from value.
let relabeled: fn(amount: Int) -> Int = identity
```

At call boundaries, a supplied `T` may be wrapped once for a standard `Optional[T]` parameter; see [optional arguments](optionals.md#passing-optional-arguments). This also applies to constructor fields and alternative payloads. Bindings, assignments, returns, defaults, and collection elements retain exact Optional compatibility.

There are no implicit numeric conversions, optional unwrapping, result wrapping, structural record conversions, unions, or nullable references. An integer literal has type `Int` even under an expected `Float`; use the [explicit conversion API](../basics/numbers-and-booleans.md#numeric-conversion). The type checker does not choose an arbitrary common type for incompatible values.

## Propagating context

An expected type comes from the place a value is used: a local annotation, assignment target, return declaration, parameter after generic substitution, record field, or alternative payload.

That type can guide the expressions inside parentheses, list elements, constructor fields, and case payloads. It can supply missing type arguments for a uniquely identified constructor such as `none`, `ok`, or `error`.

Context does not resolve an ambiguous unqualified case name or change a type an expression already determines for itself.

```manuscript
type Input:
    names: List[Optional[String]]

let input = Input(names: [none, some(value: "Ada")])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, String] = ok(value: 1)
let failure: Result[Int, String] = error(cause: "unavailable")
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(value: 1)
```

The compiler rejects expressions whose type cannot be determined. It does not silently assign a dynamic or unknown type.

| Expression without an annotation | What can be inferred |
| --- | --- |
| `none` or `[]` | Not enough information to determine the payload or element type. |
| `ok(value: 1)` | The success is Int, but the error type is still unknown. |
| `some(value: 1)` | The complete type is Optional[Int]. |
| `[none, some(value: 1)]` | The typed some value supplies enough context for List[Optional[Int]]. |

A list is rejected if its independently typed elements disagree.

Operators and try do not pass an expected result type backward into their operands. Their operands must determine their own types first. For example, knowing that the value unwrapped by try should be Int does not tell the compiler which error type an incomplete Result constructor should have.

```manuscript
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

Every declaration's referenced types must resolve and every application must satisfy arity and bounds. Generic bodies are checked under declared bounds. Public signatures satisfy [public type visibility](records.md#public-data-surfaces), and recursive concrete layouts satisfy [guarded recursion](records.md#recursive-data). These checks happen before native code is generated.

Runtime cancellation and resource closed-state errors do not alter static assignability. Their separate contracts remain governed by the existing runtime and reference chapters.
