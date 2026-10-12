+++
title = "Generics and bounds"
weight = 18
+++

# Generics and bounds

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A generic type describes a family of types using type arguments. The arguments make the element or result types visible wherever the type is used.

Generics use brackets.

```text
List[String]
Map[String, Int]
Optional[String]
Result[Decimal, DiscountError]
```

These are type expressions: a list of text, a map from text to integers, optional text, and a decimal result with an application-defined error type.

## Bounds

The complete compiler-defined bound list is `Shareable`, `Equal`, and `Hashable`; these express properties the compiler must verify rather than user-supplied operations. Other requirements use ordinary operation contracts, including contracts imported from the standard library such as Closeable; adding a library facility does not add a compiler bound. Generic declarations use `[T, U]`, with bounds `T: Bound` or intersections such as `T: Shareable & Hashable`.

| Bound | Required property |
| --- | --- |
| `Shareable` | Value is safe for concurrent access |
| `Equal` | Type supports eligible value equality |
| `Hashable` | Type supports hashing, which requires equality |
| A named operation contract | Type supplies the required operations through an explicit implementation |

A bound describes what generic code can rely on. For example, `T: Shareable` expresses a shareability requirement on `T`; it does not extend a resource lifetime or register cleanup.

Bounds are checked at every application. `Hashable` implies `Equal`, and `Equal` implies `Shareable`, both for bound satisfaction and assumptions available when checking generic bodies. Named contract bounds require an applicable explicit implementation, not merely matching method names; they do not imply `Shareable` for the implementing concrete type. Plain contract value types do not promise sharing. A shared `Contract & Shareable` value type satisfies both the named contract bound and `Shareable`; neither form adds equality or hashing.

`Shareable`, `Equal`, and `Hashable` are not standalone source value types, generic type arguments, contract-view constructors, or user implementation targets. Besides its use as a bound, `Shareable` may refine an operation contract application in a [shared view type](contracts.md#shared-contract-views), such as `List[ReadValue[Int] & Shareable]`. Their compiler-known marker identities do not make them ordinary operation contracts. Intrinsic type and bound names cannot be redefined by module declarations, imports, or type parameters; see [module name resolution](../../modules-and-capabilities/modules/declarations.md).

```text
# Rejected: a compiler bound is not a parameter type.
fn invalid_parameter(value: Shareable) -> Unit:
    return

# Rejected: Equal is not a type argument.
let invalid_argument = identity[Equal](value: 1)
# Rejected: no source view constructor for a compiler bound.
let invalid_view = Shareable(value: 1)
```

`impl Equal for DataType` is also rejected; eligibility follows compiler derivation rather than a source implementation. A declaration such as `fn invalid[Hashable](value: Hashable) -> Unit:` cannot redefine `Hashable` as its type parameter.

## Declarations and applications

```text
type Box[T]:
    value: T

fn identity[T](value: T) -> T:
    return value

fn same[T: Equal](left: T, right: T) -> Bool:
    return left == right

let box = Box[Int](value: 1)
let exact = identity[Int](value: 1)
let inferred = identity(value: 1)
```

Type parameters are ordered and their names unique. An application supplies exactly one argument per parameter. Default type arguments, higher-kinded parameters, type aliases, and variadic type parameters are unsupported. Records, alternatives, interfaces, and named functions may declare generic parameters. Implementation blocks use the receiver type declaration's parameters and inherit applicable bounds from the type and interface declarations. Anonymous functions, contract operations, and implementation methods cannot declare their own type parameters. Methods inherit the parameters used in their implementation's receiver; see [generic implementations](contracts.md#generic-implementations) for receiver matching, bound checking, and overlap rejection.

Applications are invariant: `Box[Int]` and `Box[Float]` are distinct types. A generic declaration is not an unapplied type or function value. A generic function passed as a value must be explicitly specialized, for example `identity[Int]`.

## Inference from arguments

A function call may omit type arguments only when independently typed supplied argument expressions uniquely determine every parameter. The compiler matches argument types against declared parameter types, including invariant nested applications, then checks bounds and arguments after substitution. Repeated occurrences must determine the same type. No common superclass, implicit union, or numeric widening is inferred.

```text
fn choose[T](first: T, second: T) -> T:
    return first

let value = choose(first: 1, second: 2)  # T = Int
# Rejected: conflicting evidence for T.
let mixed = choose(first: 1, second: 2.0)
```

Result annotations do not infer function type arguments. Empty lists, `none`, and other expressions requiring context cannot independently provide evidence. Once other arguments determine all parameters, substituted parameter types provide context to those expressions. This process does not reorder evaluation.

```text
fn count[T: Shareable](values: List[T]) -> Int:
    return 0

let known = count[Int](values: [])
# Rejected: the empty list does not determine T.
let unknown = count(values: [])
```

Generic data constructors follow the same field/payload inference rule, but an expected data application may supply their type arguments before field checking. Thus `let box: Box[Int] = Box(value: 1)` is valid. A unique complete application must result; a constructor cannot invent an unused type parameter.

## Body checking and well-formedness

A generic body is checked once against declared bounds. An unconstrained `T` cannot be compared with `==`, used as a map key, or called through a contract operation. Bounds expose only their declared properties.

```text
# Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left: T, right: T) -> Bool:
    return left == right

type Keys[T: Shareable & Hashable]:
    values: Set[T]
```

Every nested application must satisfy its bounds under enclosing generic assumptions. Omitting the bounds from `Keys` is rejected even if all later uses happen to supply `Int`.

The same rule checks a generic implementation once under its inherited parameters and bounds. Its method bodies cannot rely on properties absent from the inherited bounds. Matching the receiver determines the implementation arguments; all implementation bounds must hold before its operations or views are available. Bounds may restrict a single implementation's availability, but are ignored when rejecting overlapping implementations. A concrete implementation cannot specialize a pair already covered by a generic block.

## Finite recursive applications

Recursive declarations follow [layout rules](records.md#recursive-data). Separately, the compiler requires a finite regular family of recursive generic applications. Along a recursive generic cycle, arguments preserve the original parameters one-to-one in their original positions. `Tree[T: Shareable]` with `children: List[Tree[T]]` is allowed. Substituting concrete arguments, reordering them, or expanding them on a recursive cycle is rejected; `Grow[T]` containing `List[Grow[List[T]]]` would create an infinite application family. This regularity check follows recursive type references even through function signatures or contracts: an indirect runtime representation does not permit infinitely expanding static instantiations.

The same finite-application requirement covers generic function calls and specialized function values. Follow specialization dependencies through the whole module graph; on a recursive function cycle, the composed substitution must preserve the starting function's type parameters one-to-one in their original positions. Nonrecursive calls may construct different type arguments. Reject expanding recursive specialization before Go emission, even when the recursive call is unreachable at runtime. This prevents both an infinite monomorphization worklist and generic recursion that the Go backend cannot represent.

```text
fn repeat[T: Shareable](value: T) -> Never:
    return repeat[T](value: value)  # Regular specialization; allowed.

fn grow[T: Shareable](value: T) -> Never:
    return grow[List[T]](value: [value])  # Rejected: expanding specialization.
```

Apply the check to mutual recursion and references such as `grow[List[T]]` stored as function values, not only direct self-calls. Include generic implementation method calls and bound methods in specialization dependencies under their inherited receiver parameters. Generated-code compilation errors are not a substitute for a source diagnostic.

## Built-in requirements

[Collections](collections.md) require shareable contents. Map keys and set elements additionally require hashing. See [equality and hashing](equality-and-hashing.md) for the relationship between these properties.

`Shareable` is a compiler-defined bound derived from eligible immutable components and shared contract views, or declared by audited native implementations. It is not an operation contract or a source implementation target. Function types do not satisfy it, so records with function fields cannot derive sharing. The separate [callable sharing rules](../../ownership-and-cleanup/values/sharing.md#function-values) govern closures and generic forwarding. Sharing does not register cleanup or extend a resource's open lifetime.

[Previous: Operation contracts](contracts.md) · [Next: Type compatibility and expected types](compatibility.md)
