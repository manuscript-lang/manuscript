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

## Reuse a calculation without losing its types

A function that compares two integer values can declare `Int` parameters. If the same operation is needed for strings, copying the function creates two bodies to maintain. A type parameter names the part that varies, while a bound states which operations that type must support.

Save as `same.ms` and run `ms run same.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"true\nfalse\ntrue\n"} -->
```manuscript
fn same[T: Equal](left: T, right: T) Bool:
    return left == right

export fn main() Int:
    print(same(12, 12))
    print(same("draft", "published"))
    print(same[Int](4, 4))
    return 0
```

```text
true
false
true
```

In the first call `T` is `Int`; in the second it is `String`. Both arguments must be the same type. `same(12, "12")` is rejected, because one `T` cannot mean both types in the same call. The third call writes the type argument explicitly; the first two infer it from their arguments.

`Equal` is needed because the body uses `==`. Removing the bound makes the declaration invalid even if today's callers only use integers. A generic body must work for every type its declaration permits. It cannot inspect an unknown value at runtime to discover extra methods: add the necessary bound, or accept a callback that performs the operation.

Collections use the same idea. `List[String]` and `List[Int]` share the list operations, but their element types remain distinct. Generics preserve compiler-visible types; they do not introduce an `any` value or runtime reflection. See [interfaces](contracts.md) when the varying part is behavior supplied by an implementation.

## Bounds

Declare parameters as `[T, U]` with bounds such as `T: Equal` or `T: Read & Closeable`. A bound must resolve to an interface. Parameters are in scope in their bounds (`T: Compare[T]` is valid, `T: T` is not). Don't name a parameter `Error`; use `E`. `Error` is a record, not an interface or a bound; use it directly when a helper needs its `message`, `kind`, or `details`.

| Bound | Required property |
| --- | --- |
| `Equal` | Values can be compared by their contents with `==` and `!=` |
| `Comparable` | Values have an order: `a.compare(b)` is negative, zero, or positive. Int, Float, String, Decimal, BigInt, Duration, Instant, and Timestamp qualify; other types opt in with `impl Comparable` |
| `Hashable` | Values can be map keys or set elements; also supports equality |
| `Clonable` | `value.clone()` returns an independent copy, so a generic body can keep a value it only borrows. Every type qualifies except a resource (`Closeable`), a type holding one, a native type without a `clone` of its own (`Regex`, `Pipe`), a function value, and any type holding one of those. Generic code that copies a value of `T` (`xs.take(1)`, `xs.concat(ys)`, keeping a borrowed argument) declares `T: Clonable` |
| `Data` | Values hold no resource, function, interface value, or runtime handle, so they can cross a byte boundary: `json.parse`, `json.stringify`, and typed JSON stream codecs require it. Promises and pipes do not require this bound. Import it from `@std/core.ms`. Records and enums qualify when every part does; `Closeable` types never do; of the collections `List` qualifies, and a `Map[String, T]` when `T` does (it is a JSON object), never a `Set` or a `Map` with another key type; `JsonValue` is declared `Data`, so a dynamic JSON object travels as one. A type with a `JsonEncode` implementation qualifies; the codec owns its JSON form |
| A named operation contract | Type supplies the required operations through an explicit implementation |

Bounds are checked at every application; `Hashable` implies `Equal`, and `Data` and `Hashable` imply `Clonable`. No sharing bound exists, and sharing adds no synchronization. Contract types gain no equality or hashing.

`Equal` and `Hashable` are ordinary [interfaces](equality-and-hashing.md) from `@std/core.ms`: bounds, parameter types, type arguments, and `impl` targets. Their prelude names cannot be redefined by declarations, imports, or type parameters.

```manuscript
type Key:
    id: Int

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

fn same_key(left: Equal, right: Equal) Bool:
    return left.equals(right)

fn use_view() Bool:
    return same_key(Key(1), Key(1))
```

### Make ownership part of a generic operation

A bound also explains how a helper may keep data. To make two independent copies of a value, require `Clonable` and clone explicitly. Without that bound the caller might pass a file or a function value, neither of which can be cloned.

Save as `copies.ms` and run `ms run copies.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[[1, 2], [1]]\n[1]\n"} -->
```manuscript
fn two_copies[T: Clonable](value: T) List[T]:
    return [value.clone(), value.clone()]

export fn main() Int:
    let source = [1]
    var copies = two_copies(source)
    copies[0].append(2)
    print(copies)
    print(source)
    return 0
```

```text
[[1, 2], [1]]
[1]
```

The function borrows `source` and produces two owned copies. Changing the first copy changes neither the second nor the source. The result is a `List[List[Int]]`: substituting a concrete type for `T` also substitutes it wherever `T` occurs in the result. See [ownership](references.md) for when cloning is necessary and when borrowing or moving is enough.

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
- Records, enums, interfaces, and named functions may be generic. Anonymous functions cannot declare parameters. Contract operations and methods may declare their own ([generic operations](contracts.md#generic-operations)), and implementations inherit the receiver's ([generic implementations](contracts.md#generic-implementations)).
- Higher-kinded parameters, type aliases, and variadic parameters are unsupported.
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

let same: Pair[Int] = Pair[Int](1, 2)    // Pair[Int, Int]
let mixed = Pair[Int, String](1, "x")
```

Inference runs first; a parameter it leaves undetermined takes its default, for calls and constructors alike. An undetermined parameter without a default is an error.

## Inference from arguments

A call may omit type arguments when its arguments and expected result uniquely determine every parameter. Evidence is gathered in order: independently typed arguments, then the expected result, then callbacks with known inputs. Repeated occurrences must agree. Bounds are checked after substitution. No common supertype, union, or numeric widening is inferred.

```manuscript
fn choose[T](first: T, second: T) T:
    return first

let value = choose(1, 2)  // T = Int
// Rejected: conflicting evidence for T.
let mixed = choose(1, 2.0)
```

The expected result (return type, annotation, field, argument, or callback) fills missing parameters but never overrides argument evidence or explicit specialization. A parameter in neither arguments nor result needs an explicit type argument.

```manuscript
fn fail[T](message: String) Result[T, Error]: error(Error(message))

fn first() Result[Int, Error]: fail("empty")  // T = Int
let failed: Result[Int, Error] = fail("empty")
```

Matching adds no numeric conversions, interface conversions, or `Optional` wrapping. Error types, success types, and Optional or collection applications must match exactly. Inferred function types lose default-argument omission.

Empty lists, `none`, and similar expressions give no evidence of their own; once other evidence fixes the parameters, the substituted types give them context. For a standard `T?` parameter, inference first matches an existing optional, then a plain payload ([optional arguments](optionals.md#passing-optional-arguments)). Evaluation order is unchanged.

```manuscript
fn count[T](values: List[T]) Int:
    return 0

let known = count[Int]([])
// Rejected: the empty list does not determine T.
let unknown = count([])
```

Generic constructors infer from fields or payloads, or from an expected application: `let box: Box[Int] = Box(value: 1)`. The result must be one complete application.

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

[Recursive data](records.md#recursive-data) may be generic only if each cycle passes the original parameters back in their original positions (composed around mutual cycles). `Tree[T]` with `Branch(left: Tree[T], right: Tree[T])` is allowed; substituting, reordering, or expanding arguments is rejected, so `Grow[T]` holding `List[Grow[List[T]]]` is an error. Nonrecursive nesting like `Box[Box[Int]]` is fine. The check covers every type reference, including function signatures and contracts.

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
