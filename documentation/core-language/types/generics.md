+++
title = "Generics and bounds"
weight = 9
+++

# Generics and bounds

A generic type describes a family of types using type arguments. The arguments make the element or result types visible wherever the type is used.

Generics use brackets.

```manuscript
List[String]
Map[String, Int]
Optional[String]
Result[Decimal, DiscountError]
```

These are type expressions: a list of text, a map from text to integers, optional text, and a decimal result with an application-defined error type.

## Bounds

`T: Equal` means values of `T` can be compared with `==` and `!=`; `T: Hashable` supplies hashing for map keys and set elements, which also require Equal. These are standard interfaces with built-in value implementations and explicit domain implementations. See [equality and hashing](equality-and-hashing.md) for examples. Generic declarations use `[T, U]`, with bounds such as `T: Equal` or `T: Read & Closeable`.

A bound must resolve to an interface. Type parameters are in scope in their bounds, so `T: Compare[T]` is valid when `Compare` is an interface, but `T: T` is not. A parameter named `Error` shadows the prelude interface: use `E: Error` rather than `Error: Error`.

| Bound | Required property |
| --- | --- |
| `Equal` | Values can be compared by their contents with `==` and `!=` |
| `Hashable` | Values can be map keys or set elements; also supports equality |
| A named operation contract | Type supplies the required operations through an explicit implementation |

Bounds are checked at every application. `Hashable` implies `Equal` for bound satisfaction and body checking. All values may be passed between operations without a sharing bound; this does not add synchronization to mutable objects. Contract types do not gain equality or hashing.

`Equal` and `Hashable` are not standalone value types, generic type arguments, view constructors, or implementation targets. Their intrinsic names cannot be redefined by module declarations, imports, or type parameters. Concurrent access requires no compiler-defined bound.

```manuscript
# Rejected: a compiler bound is not a parameter type.
fn invalid_parameter(value: Equal) -> Unit:
    return

# Rejected: Equal is not a type argument.
let invalid_argument = identity[Equal](value: 1)
# Rejected: no source view constructor for a compiler bound.
let invalid_view = Equal(value: 1)
```

`impl Equal for DataType` is also rejected; eligibility follows compiler derivation rather than a source implementation. A declaration such as `fn invalid[Hashable](value: Hashable) -> Unit:` cannot redefine `Hashable` as its type parameter.

## Declarations and applications

```manuscript
type Box[T]:
    value: T

fn identity[T](value: T) -> T:
    return value

fn same[T: Equal](left: T, right: T) -> Bool:
    return left == right

let box = Box[Int](1)
let exact = identity[Int](value: 1)
let inferred = identity(value: 1)
```

Type parameters are ordered and their names unique. An application supplies exactly one argument per parameter. Default type arguments, higher-kinded parameters, type aliases, and variadic type parameters are unsupported. Records, alternatives, interfaces, and named functions may declare generic parameters. Implementation blocks use the receiver type declaration's parameters and inherit applicable bounds from the type and interface declarations. Anonymous functions, contract operations, and implementation methods cannot declare their own type parameters. Methods inherit the parameters used in their implementation's receiver; see [generic implementations](contracts.md#generic-implementations) for receiver matching, bound checking, and overlap rejection.

Applications are invariant: `Box[Int]` and `Box[Float]` are distinct types. A generic declaration is not an unapplied type or function value. A generic function passed as a value must be explicitly specialized, for example `identity[Int]`.

## Inference from arguments

A function call may omit type arguments when its arguments and expected result uniquely determine every parameter. Independently typed arguments establish initial evidence. A known expected result then supplies missing evidence before callbacks with known inputs contribute their result types. The compiler matches argument types against declared parameter types, including invariant nested applications, then checks bounds and arguments after substitution. Repeated occurrences must determine the same type. No common superclass, implicit union, or numeric widening is inferred.

```manuscript
fn choose[T](first: T, second: T) -> T:
    return first

let value = choose(first: 1, second: 2)  # T = Int
# Rejected: conflicting evidence for T.
let mixed = choose(first: 1, second: 2.0)
```

The expected result may come from an enclosing function's return type, an annotated binding, a field, an argument, or a contextual callback. It must determine missing parameters unambiguously; a parameter absent from both the arguments and result still needs an explicit type argument. Existing argument evidence is preserved. Conflicting types are rejected, and explicit specialization is never overridden.

```manuscript
fn fail[T](message: String) -> Result[T, String]: error(message)

fn first() -> Result[Int, String]: fail("empty")  # T = Int
let failed: Result[Int, String] = fail("empty")
```

Result matching preserves nominal types, invariant generic applications, and function argument labels. It does not introduce numeric conversions, implicit interface views, or wrapping a plain return value in `Optional`. Existing conversion of an implemented domain error to `Error` remains valid, including a `Result` error payload. A parameter of type `Result[T, Error]` infers `T` from the success type of an argument such as `Result[Int, Failure]` and widens the error, so `describe(r: failing())` needs no `[Int]`. This also works when an earlier argument has determined the error parameter as `Error`, or when the supplied Result is wrapped once for an `Optional[Result[T, Error]]` parameter. The Result success type and existing Optional or collection applications still match exactly. Inference preserves the concrete error type already determined by arguments. Bounds are checked after inference, and inferred function types do not retain default-argument omission permissions.

Empty lists, `none`, and other expressions requiring context cannot independently provide evidence. Once arguments or the expected result determine the needed parameters, substituted parameter types provide context to those expressions. For a standard `Optional[T]` parameter, inference first matches an existing optional, then permits a plain payload to determine `T`; see [optional arguments](optionals.md#passing-optional-arguments). This process does not reorder evaluation.

```manuscript
fn count[T](values: List[T]) -> Int:
    return 0

let known = count[Int](values: [])
# Rejected: the empty list does not determine T.
let unknown = count(values: [])
```

Generic data constructors infer from their fields or payloads, and an expected data application may supply their type arguments before field checking. Thus `let box: Box[Int] = Box(value: 1)` is valid. A unique complete application must result; a constructor cannot invent an unused type parameter.

## Body checking and well-formedness

A generic body is checked once against declared bounds. An unconstrained `T` cannot be compared with `==`, used as a map key, or called through a contract operation. Bounds expose only their declared properties.

```manuscript
# Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left: T, right: T) -> Bool:
    return left == right

type Keys[T: Hashable]:
    values: Set[T]
```

Every nested application must satisfy its bounds under enclosing generic assumptions. Omitting the bounds from `Keys` is rejected even if all later uses happen to supply `Int`.

The same rule checks a generic implementation once under its inherited parameters and bounds. Its method bodies cannot rely on properties absent from the inherited bounds. Matching the receiver determines the implementation arguments; all implementation bounds must hold before its operations or views are available. Bounds may restrict a single implementation's availability, but are ignored when rejecting overlapping implementations. A concrete implementation cannot specialize a pair already covered by a generic block.

## Finite recursive applications

Direct and mutual [recursive data](records.md#recursive-data) are supported. Separately, the compiler requires a finite regular family of recursive generic applications. Along a recursive generic cycle, arguments preserve the original parameters one-to-one in their original positions. `Tree[T]` with a case `Branch(left: Tree[T], right: Tree[T])` is allowed. Substituting concrete arguments, reordering them, or expanding them on a recursive cycle is rejected; `Grow[T]` containing `List[Grow[List[T]]]` would create an infinite application family. Nonrecursive nesting such as `Box[Box[Int]]` is allowed. For mutually recursive declarations, substitutions are composed around the cycle; the resulting arguments must match the starting parameters. This regularity check follows all declared type references, including generic arguments (even unused parameters), function signatures, and contracts: an indirect runtime representation does not permit infinitely expanding static instantiations.

The same finite-application requirement covers generic function calls and specialized function values. Follow specialization dependencies through the whole module graph; on a recursive function cycle, the composed substitution must preserve the starting function's type parameters one-to-one in their original positions. Nonrecursive calls may construct different type arguments. Reject expanding recursive specialization before code generation, even when the recursive call is unreachable at runtime. This keeps recursive specialization finite.

```manuscript
fn repeat[T](value: T) -> Never:
    return repeat[T](value: value)  # Regular specialization; allowed.

fn grow[T](value: T) -> Never:
    return grow[List[T]](value: [value])  # Rejected: expanding specialization.
```

Apply the check to mutual recursion and references such as `grow[List[T]]` stored as function values, not only direct self-calls. Include generic implementation method calls and bound methods in specialization dependencies under their inherited receiver parameters. Generated-code compilation errors are not a substitute for a source diagnostic.

## Built-in requirements

`List[T]`, `Queue[T]`, `Synchronized[T]`, and collection values accept arbitrary value types, including functions and contract views. Map keys and set elements require `Hashable`. Equality uses the interfaces described in [equality and hashing](equality-and-hashing.md). Sharing does not register cleanup or extend a resource's open lifetime.
