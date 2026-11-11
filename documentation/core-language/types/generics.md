+++
title = "Generics and bounds"
weight = 9
+++

# Generics and bounds

Generics let one function or data type work with several concrete types while keeping its inputs and results known to the compiler. Type arguments go in brackets.

```manuscript
List[String]
Map[String, Int]
String?
Result[Decimal, DiscountError]
```

## Bounds

Declare parameters as `[T, U]` with bounds such as `T: Equal` or `T: Read & Closeable`. A bound must resolve to an interface. Parameters are in scope in their bounds (`T: Compare[T]` is valid, `T: T` is not). Don't name a parameter `Error`; use `E`. `Error` is a type, not an interface or a bound; use it directly when a helper needs its `message`, `kind`, or `details`.

| Bound | Required property |
| --- | --- |
| `Equal` | Values can be compared by their contents with `==` and `!=` |
| `Comparable` | Values have an order: `a.compare(b)` is negative, zero, or positive. Int, Float, String, Decimal, BigInt, Duration, Instant, and Timestamp qualify; other types opt in with an own `compare` |
| `Hashable` | Values can be map keys or set elements; also supports equality |
| `Clonable` | `value.clone()` returns an independent copy, so a generic body can keep a value it only borrows. Every type qualifies except a resource (`Closeable`), a type holding one, a native type without a `clone` of its own (`Regex`, `Pipe`), a function value, and any type holding one of those. Generic code that copies a value of `T` (`xs.take(1)`, `xs.concat(ys)`, keeping a borrowed argument) declares `T: Clonable` |
| `Data` | Values hold no resource, function, interface value, or runtime handle, so they can cross a byte boundary: `json.parse`, `json.stringify`, and typed JSON stream codecs require it. Promises and pipes do not require this bound. Import it from `@std/core.ms`. Types and enums qualify when every part does; `Closeable` types never do; of the collections `List` qualifies, and a `Map[String, T]` when `T` does (it is a JSON object), never a `Set` or a `Map` with another key type; `JsonValue` is declared `Data`, so a dynamic JSON object travels as one. A type with a `JsonEncode` implementation qualifies; the codec owns its JSON form |
| A named operation contract | Type supplies the required operations through an explicit implementation |

Bounds are checked at every application; `Hashable` implies `Equal`, and `Data` and `Hashable` imply `Clonable`. No sharing bound exists, and sharing adds no synchronization. Contract types gain no equality or hashing.

`Equal` and `Hashable` are ordinary [interfaces](equality-and-hashing.md) from `@std/core.ms`: bounds, parameter types and type arguments. Their prelude names cannot be redefined by declarations, imports, or type parameters.

```manuscript
type Key:
    id: Int

fn Key.equals(other: Key) Bool:
    return self.id == other.id

fn same_key(left: Equal, right: Equal) Bool:
    return left.equals(right)

fn use_view() Bool:
    return same_key(Key(1), Key(1))
```

## Declarations and applications

```manuscript
type Box[T]:
    value: T

fn identity[T](value: T) T:
    return value

fn same[T: Equal](left: T, right: T) Bool:
    return left == right

box := Box[Int](1)
exact := identity[Int](1)
inferred := identity(1)
```

- Parameter names are unique; an application supplies one argument each, except trailing [defaults](#default-type-arguments).
- Types, enums, interfaces, and named functions may be generic. Anonymous functions cannot declare parameters. Contract operations and methods may declare their own ([generic operations](contracts.md#generic-operations)), and a receiver names the type's parameters ([generic receivers](contracts.md#generic-receivers)).
- Higher-kinded parameters and variadic parameters are unsupported. A [type alias](named-types.md#aliases) may take parameters.
- Applications are invariant: `Box[Int]` is not `Box[Float]`.
- A generic function used as a value must be specialized: `identity[Int]`.

## Default type arguments

A parameter may declare `= Type` as a default. Later parameters then need defaults too. A default may name earlier parameters, not itself or later ones, and must satisfy the bounds.

```manuscript
type Pair[A, B = A]:
    first: A
    second: B

fn parse[T = String](text: String) T?:
    return none

same: Pair[Int] := Pair[Int](1, 2)    // Pair[Int, Int]
mixed := Pair[Int, String](1, "x")
```

Inference runs first; a parameter it leaves undetermined takes its default, for calls and constructors alike. An undetermined parameter without a default is an error.

## Inference from arguments

A call may omit type arguments when its arguments and expected result uniquely determine every parameter. Evidence is gathered in order: independently typed arguments, then the expected result, then callbacks with known inputs. Repeated occurrences must agree. Bounds are checked after substitution. No common supertype, union, or numeric widening is inferred.

```manuscript
fn choose[T](first: T, second: T) T:
    return first

value := choose(1, 2)  // T = Int
// Rejected: conflicting evidence for T.
mixed := choose(1, 2.0)
```

The expected result (return type, annotation, field, argument, or callback) fills missing parameters but never overrides argument evidence or explicit specialization. A parameter in neither arguments nor result needs an explicit type argument.

```manuscript
fn fail[T](message: String) Result[T, Error]: error(Error(message))

fn first() Result[Int, Error]: fail("empty")  // T = Int
failed: Result[Int, Error] := fail("empty")
```

Matching adds no numeric conversions, interface conversions, or `Optional` wrapping. Error types, success types, and Optional or collection applications must match exactly. Inferred function types lose default-argument omission.

Empty lists, `none`, and similar expressions give no evidence of their own; once other evidence fixes the parameters, the substituted types give them context. For a standard `T?` parameter, inference first matches an existing optional, then a plain payload ([optional arguments](optionals.md#passing-optional-arguments)). Evaluation order is unchanged.

```manuscript
fn count[T](values: List[T]) Int:
    return 0

known := count[Int]([])
// Rejected: the empty list does not determine T.
unknown := count([])
```

Generic constructors infer from fields or payloads, or from an expected application: `box: Box[Int] = Box(value: 1)`. The result must be one complete application.

## Body checking and well-formedness

A generic body is checked once against its declared bounds, which expose only their declared properties. An unconstrained `T` cannot use `==`, be a map key, or call contract operations.

```manuscript
// Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left: T, right: T) Bool:
    return left == right

type Keys[T: Hashable]:
    values: Set[T]
```

Every nested application must satisfy its bounds under the enclosing assumptions; omitting them from `Keys` is rejected even if every use supplies `Int`.

A generic implementation is likewise checked once under its inherited bounds. Matching the receiver determines its arguments, and its bounds must hold before its operations or views exist. Bounds are ignored when rejecting overlapping implementations, and a concrete implementation cannot specialize a pair a generic block already covers.

## Finite recursive applications

[Recursive data](named-types.md#recursive-data) may be generic only if each cycle passes the original parameters back in their original positions (composed around mutual cycles). `Tree[T]` with `Branch(left: Tree[T], right: Tree[T])` is allowed; substituting, reordering, or expanding arguments is rejected, so `Grow[T]` holding `List[Grow[List[T]]]` is an error. Nonrecursive nesting like `Box[Box[Int]]` is fine. The check covers every type reference, including function signatures and contracts.

Generic function calls and specialized function values follow the same rule across the module graph: a recursive cycle must preserve the starting type parameters one-to-one. Nonrecursive calls may use other arguments. Expanding specialization is rejected before code generation, even if unreachable.

```manuscript
fn repeat[T](value: T) Never:
    return repeat[T](value)  // Regular specialization; allowed.

fn grow[T](value: T) Never:
    return grow[List[T]]([value])  // Rejected: expanding specialization.
```

The check also covers mutual recursion, function values such as `grow[List[T]]`, and generic implementation method calls.

## Built-in requirements

`List[T]`, `Queue[T]`, and other collections accept any value type, including functions and contract views. Map keys and set elements require `Hashable` ([equality and hashing](equality-and-hashing.md)).

## Type sets

`type Name = A | B | C` names a closed set of types. A set is only a bound: `T: Name` accepts exactly its members, and nothing exists at run time (no tag, no layout, no `match`). Generic code is monomorphized, so each instance is compiled for one member.

```manuscript
type Number = Int | Int8 | Float | Float32

fn total[T: Number](values: List[T]) T:
    var sum: T = 0
    for v in values:
        sum += v
    return sum
```

- Members are concrete types, not type parameters or interfaces. A set may name another set; its members are flattened in.
- Inside the body, `+`, `-`, `*`, `/` and comparisons work on a `T` whose members are all numeric, and the literal `0` is the zero of every member. Each instance keeps its own arithmetic: `Int8` overflow faults and `Float32` rounds to binary32.
- A set cannot be a value type: `fn f(x: Number)` is rejected with `Number is a type set, which constrains a type parameter and has no values`. A type outside the set is rejected where the argument is checked: `String is not a member of the type set Number`.
- A method may be declared once on a set declared in the same module: `fn Length.double() Self:` with `type Length = Meters | Feet` gives `Meters` and `Feet` each the method, with `Self` the receiving member. The module may declare methods only on types it owns, as for any receiver. The members must be concrete types.
- `@std/collections/collections.ms` exports `Numeric`, the integer and float types `List.sum` adds.
