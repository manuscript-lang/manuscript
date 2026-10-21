+++
title = "Generics and bounds"
weight = 9
+++

# Generics and bounds

Generic types take type arguments in brackets.

```manuscript
List[String]
Map[String, Int]
Optional[String]
Result[Decimal, DiscountError]
```

## Bounds

Declare parameters as `[T, U]` with bounds such as `T: Equal` or `T: Read & Closeable`. A bound must resolve to an interface. Parameters are in scope in their bounds (`T: Compare[T]` is valid, `T: T` is not). Don't name a parameter `Error`; write `E: Error`.

| Bound | Required property |
| --- | --- |
| `Equal` | Values can be compared by their contents with `==` and `!=` |
| `Comparable` | Values have an order: `a.compare(Comparable(value: b))` is negative, zero, or positive. Int, Float, String, Decimal, BigInt, Duration, Instant, and Timestamp qualify; other types opt in with `impl Comparable` |
| `Hashable` | Values can be map keys or set elements; also supports equality |
| A named operation contract | Type supplies the required operations through an explicit implementation |

Bounds are checked at every application, and `Hashable` implies `Equal`. No sharing bound exists, and sharing adds no synchronization. Contract types gain no equality or hashing.

`Equal` and `Hashable` are ordinary [interfaces](equality-and-hashing.md) from `@std/core.ms`: bounds, parameter types, type arguments, explicit views (`Equal(value: x)`), and `impl` targets. Their prelude names cannot be redefined by declarations, imports, or type parameters.

```manuscript
type Key:
    id: Int

impl Equal for Key:
    fn equals(other: Equal) Bool:
        return true

fn accepts(value: Equal) Unit:
    return

fn use_view() Unit:
    accepts(Equal(Key(1)))
```

## Declarations and applications

```manuscript
type Box[T]:
    value: T

fn identity[T](value: T) T:
    return value

fn same[T: Equal](left: T, right: T) Bool:
    return left == right

let box = Box[Int](1)
let exact = identity[Int](1)
let inferred = identity(1)
```

- Parameter names are unique; an application supplies one argument each, except trailing [defaults](#default-type-arguments).
- Records, alternatives, interfaces, and named functions may be generic. Anonymous functions, contract operations, and implementation methods cannot declare parameters; implementations inherit the receiver's ([generic implementations](contracts.md#generic-implementations)).
- Higher-kinded parameters, type aliases, and variadic parameters are unsupported.
- Applications are invariant: `Box[Int]` is not `Box[Float]`.
- A generic function used as a value must be specialized: `identity[Int]`.

## Default type arguments

A parameter may declare `= Type` as a default. Later parameters then need defaults too. A default may name earlier parameters, not itself or later ones, and must satisfy the bounds.

```manuscript
type Pair[A, B = A]:
    first: A
    second: B

fn parse[T = String](text: String) Optional[T]:
    return none

let same: Pair[Int] = Pair[Int](1, 2)    # Pair[Int, Int]
let mixed = Pair[Int, String](1, "x")
```

Inference runs first; a parameter it leaves undetermined takes its default, for calls and constructors alike. An undetermined parameter without a default is an error.

## Inference from arguments

A call may omit type arguments when its arguments and expected result uniquely determine every parameter. Evidence is gathered in order: independently typed arguments, then the expected result, then callbacks with known inputs. Repeated occurrences must agree. Bounds are checked after substitution. No common supertype, union, or numeric widening is inferred.

```manuscript
fn choose[T](first: T, second: T) T:
    return first

let value = choose(1, 2)  # T = Int
# Rejected: conflicting evidence for T.
let mixed = choose(1, 2.0)
```

The expected result (return type, annotation, field, argument, or callback) fills missing parameters but never overrides argument evidence or explicit specialization. A parameter in neither arguments nor result needs an explicit type argument.

```manuscript
import {TextError} from "@std/core.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))

fn first() Result[Int, TextError]: fail("empty")  # T = Int
let failed: Result[Int, TextError] = fail("empty")
```

Matching adds no numeric conversions, implicit interface views, or `Optional` wrapping. A domain error implementing `Error` still widens to `Error`, so a `Result[T, Error]` parameter infers `T` from `Result[Int, Failure]`. Success types and other Optional or collection applications must match exactly. Inferred function types lose default-argument omission.

Empty lists, `none`, and similar expressions give no evidence of their own; once other evidence fixes the parameters, the substituted types give them context. For a standard `Optional[T]` parameter, inference first matches an existing optional, then a plain payload ([optional arguments](optionals.md#passing-optional-arguments)). Evaluation order is unchanged.

```manuscript
fn count[T](values: List[T]) Int:
    return 0

let known = count[Int]([])
# Rejected: the empty list does not determine T.
let unknown = count([])
```

Generic constructors infer from fields or payloads, or from an expected application: `let box: Box[Int] = Box(value: 1)`. The result must be one complete application.

## Body checking and well-formedness

A generic body is checked once against its declared bounds, which expose only their declared properties. An unconstrained `T` cannot use `==`, be a map key, or call contract operations.

```manuscript
# Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left: T, right: T) Bool:
    return left == right

type Keys[T: Hashable]:
    values: Set[T]
```

Every nested application must satisfy its bounds under the enclosing assumptions; omitting them from `Keys` is rejected even if every use supplies `Int`.

A generic implementation is likewise checked once under its inherited bounds. Matching the receiver determines its arguments, and its bounds must hold before its operations or views exist. Bounds are ignored when rejecting overlapping implementations, and a concrete implementation cannot specialize a pair a generic block already covers.

## Finite recursive applications

[Recursive data](records.md#recursive-data) may be generic only if each cycle passes the original parameters back in their original positions (composed around mutual cycles). `Tree[T]` with `Branch(left: Tree[T], right: Tree[T])` is allowed; substituting, reordering, or expanding arguments is rejected, so `Grow[T]` holding `List[Grow[List[T]]]` is an error. Nonrecursive nesting like `Box[Box[Int]]` is fine. The check covers every type reference, including function signatures and contracts.

Generic function calls and specialized function values follow the same rule across the module graph: a recursive cycle must preserve the starting type parameters one-to-one. Nonrecursive calls may use other arguments. Expanding specialization is rejected before code generation, even if unreachable.

```manuscript
fn repeat[T](value: T) Never:
    return repeat[T](value)  # Regular specialization; allowed.

fn grow[T](value: T) Never:
    return grow[List[T]]([value])  # Rejected: expanding specialization.
```

The check also covers mutual recursion, function values such as `grow[List[T]]`, and generic implementation method calls.

## Built-in requirements

`List[T]`, `Queue[T]`, and other collections accept any value type, including functions and contract views. Map keys and set elements require `Hashable` ([equality and hashing](equality-and-hashing.md)).
