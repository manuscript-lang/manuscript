+++
title = "Type compatibility and expected types"
weight = 10
+++

# Type compatibility and expected types

A value's type must match the type required at its position: annotations, assignments, arguments, returns, fields, and collection elements. An `Int` is not a `Float`, and types with equal fields are not interchangeable.

`Never` expressions fit anywhere. `?` needs the same error type as the enclosing function ([error compatibility](../errors/propagation.md#error-compatibility)).

## Exact and nominal identity

| Type form | Identity and compatibility |
| --- | --- |
| Built-in | Fixed compiler or standard identity |
| Type or enum | Defining module, declaration, and ordered type arguments; matching fields or cases do not establish compatibility |
| Contract view | Nominal contract application; a type with a declared implementation [converts implicitly](contracts.md#interface-conversion) where the interface is expected |
| Generic application | Exact declaration and every ordered argument |
| Function | Exact parameter types in declaration order and result type; parameter names are not part of identity; no variance |

A generic bound grants properties, not subtyping.

Type positions use [ordinary name resolution](../modules/declarations.md#names-and-declaration-order), and a value that shadows a type name is an error. Unqualified cases follow [enum lookup](alternatives.md#construction-and-identity). An expected type cannot override a lexical binding or choose between ambiguous cases.

`Equal` and `Hashable` are [standard interfaces](equality-and-hashing.md) that work as bounds and as parameter types. Only generic bounds can be combined; value types have no intersection or refinement syntax.

<!-- manuscript-example: {"mode":"error","contains":"expected fn(Int) String","given":[]} -->
```manuscript
fn identity(value: Int) Int:
    return value

exact: fn(Int) Int := identity
// Rejected: the result type differs.
wrong: fn(Int) String := identity
```

An expected `T?` accepts a plain `T` and wraps it as the present case. This works in arguments, constructor fields, enum payloads, annotated bindings, assignments, returns, defaults, and collection elements ([optional values](optionals.md#passing-optional-arguments)). It wraps one layer and never changes a numeric type.

The language has no implicit numeric conversion, optional unwrapping, result wrapping, structural type conversion, union, or nullable reference. An integer literal is `Int` even where `Float` is expected; use the [explicit conversion API](../basics/numbers-and-booleans.md#numeric-conversion).

## Propagating context

An expected type comes from an annotation, assignment target, return declaration, substituted parameter, field, or enum payload. It guides parenthesized expressions, list elements, constructor fields, and case payloads.

It also supplies missing type arguments for a uniquely identified `null`, `ok`, or `error`. It never resolves an ambiguous case name or overrides a type that the expression already determines.

<!-- manuscript-example: {"mode":"error","contains":"cannot infer","given":[]} -->
```manuscript
type Input:
    names: List[String?]

input := Input([null, "Ada"])
nested: List[List[Int]] := [[], [1]]
success: Result[Int, Error] := ok(1)
failure: Result[Int, Error] := error(Error("unavailable"))
// Rejected: the result error type cannot be inferred from ok's payload.
incomplete := ok(1)
```

The checker rejects an expression whose type it cannot determine.

| Expression without an annotation | What can be inferred |
| --- | --- |
| `null` or `[]` | Not enough information to determine the payload or element type. |
| `ok(value: 1)` | The success is Int, but the error type is still unknown. |
| `1` | Int; it wraps only where an `Int?` is expected. |
| `[null, 1]` | Not enough information: a plain `1` does not make the list optional. Annotate `List[Int?]`. |

A list whose independently typed elements disagree is rejected.

Operators and `?` normally require operands to determine their own types first. The exception is [arithmetic over numeric literals](../basics/numbers-and-booleans.md#sized-numbers): it takes an expected sized numeric type, including the payload of an expected optional, without changing numeric kind or narrowing a named value.

<!-- manuscript-example: {"mode":"error","contains":"cannot infer","given":[]} -->
```manuscript
fn known() Result[Int, Error]:
    number: Int := Result[Int, Error].ok(1)?
    return ok(number)

fn unknown() Result[Int, Error]:
    // Rejected: the `?` operand's error type is undetermined.
    number: Int := ok(1)?
    return ok(number)
```

Likewise `[] == []` is ill typed even where `Bool` is expected; annotate or qualify incomplete operands. `Never` operands follow the [operator candidate rules](../basics/expressions.md#never-operands).

Generic inference combines argument types with an unambiguous expected result. The expected result fills gaps but never overrides what the arguments show ([generics](generics.md#inference-from-arguments)). A generic function value must be explicitly specialized before it can be checked against a function type. Anonymous functions follow [callback inference](../functions/function-values-and-closures.md#contextual-callback-inference).

## Validation boundaries

Before code generation the checker verifies that:

- referenced types resolve, and type applications meet their arity and bounds;
- generic bodies type-check under their declared bounds;
- public signatures satisfy [public type visibility](named-types.md#public-data-surfaces);
- recursive generics satisfy the [finite-application rules](generics.md#finite-recursive-applications).

Runtime cancellation and closed-state errors do not affect static assignability.
