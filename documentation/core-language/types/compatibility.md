+++
title = "Type compatibility and expected types"
weight = 10
+++

# Type compatibility and expected types

A value's type must match the type required at its position: annotations, assignments, arguments, returns, fields, and collection elements. An `Int` is not a `Float`, and records with equal fields are not interchangeable.

`Never` expressions fit anywhere. `try` needs the same error type as the enclosing function ([error compatibility](../errors/propagation.md#error-compatibility)).

## Exact and nominal identity

| Type form | Identity and compatibility |
| --- | --- |
| Built-in | Fixed compiler or standard identity |
| Record or alternative | Defining module, declaration, and ordered type arguments; matching fields or cases do not establish compatibility |
| Contract view | Nominal contract application; a type with a declared implementation [converts implicitly](contracts.md#interface-conversion) where the interface is expected |
| Generic application | Exact declaration and every ordered argument |
| Function | Exact parameter types in declaration order and result type; parameter names are not part of identity; no variance |

A generic bound grants properties, not subtyping. Type positions use [ordinary name resolution](../modules/declarations.md#names-and-declaration-order); a value shadowing a type name is an error. Unqualified cases follow [alternative lookup](alternatives.md#construction-and-identity), and expected types cannot override a lexical binding or choose an ambiguous case.

`Equal` and `Hashable` are [standard interfaces](equality-and-hashing.md) usable as bounds and as parameter types. Only generic bounds can be conjoined; value types have no intersection or refinement syntax.

```manuscript
fn identity(value: Int) Int:
    return value

let exact: fn(Int) Int = identity
# Rejected: the result type differs.
let wrong: fn(Int) String = identity
```

An expected `T?` accepts a plain `T`, wrapped as the present case, in arguments, constructor fields, alternative payloads, annotated bindings, assignments, returns, defaults, and collection elements ([optional values](optionals.md#passing-optional-arguments)). It wraps one layer and never changes a numeric type.

There are no implicit numeric conversions, optional unwrapping, result wrapping, structural record conversions, unions, or nullable references. An integer literal is `Int` even where `Float` is expected; use the [explicit conversion API](../basics/numbers-and-booleans.md#numeric-conversion).

## Propagating context

An expected type comes from an annotation, assignment target, return declaration, substituted parameter, record field, or alternative payload. It guides parenthesized expressions, list elements, constructor fields, and case payloads, and supplies missing type arguments for a uniquely identified `none`, `ok`, or `error`. It never resolves an ambiguous case name or overrides a type an expression already determines.

```manuscript
type Input:
    names: List[String?]

let input = Input([none, "Ada"])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, Error] = ok(1)
let failure: Result[Int, Error] = error(Error("unavailable"))
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(1)
```

Expressions whose type cannot be determined are rejected.

| Expression without an annotation | What can be inferred |
| --- | --- |
| `none` or `[]` | Not enough information to determine the payload or element type. |
| `ok(value: 1)` | The success is Int, but the error type is still unknown. |
| `1` | Int; it wraps only where an `Int?` is expected. |
| `[none, 1]` | Not enough information: a plain `1` does not make the list optional. Annotate `List[Int?]`. |

A list whose independently typed elements disagree is rejected.

Operators and `try` do not pass an expected type back into their operands, which must determine their own types first.

```manuscript
fn known() Result[Int, Error]:
    let number: Int = try Result[Int, Error].ok(1)
    return ok(number)

fn unknown() Result[Int, Error]:
    # Rejected: the try operand's error type is undetermined.
    let number: Int = try ok(1)
    return ok(number)
```

So `[] == []` is ill typed even where `Bool` is expected; qualify or annotate incomplete operands. `Never` operands follow the [operator candidate rules](../basics/expressions.md#never-operands).

Generic inference combines argument types with an unambiguous expected result, which fills gaps without overriding argument evidence ([generics](generics.md#inference-from-arguments)). A generic function value must be explicitly specialized to check against a function type. Anonymous functions follow [callback inference](../functions/function-values-and-closures.md#contextual-callback-inference).

## Validation boundaries

Before code generation, referenced types must resolve, applications must meet arity and bounds, generic bodies are checked under declared bounds, public signatures satisfy [public type visibility](records.md#public-data-surfaces), and recursive generics satisfy [finite-application rules](generics.md#finite-recursive-applications). Runtime cancellation and closed-state errors do not affect static assignability.
