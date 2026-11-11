+++
title = "Interfaces and implementations"
weight = 7
+++

# Interfaces and implementations

An interface is an operation contract: a type satisfies it by having methods with the declared operations and signatures. Use it when callers should depend on behavior, not a data type. Signatures follow the ordinary [function rules](../functions/declarations-and-calls.md).

Save as `adjust.ms` and run `ms run adjust.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"12\n"} -->
```manuscript
interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

fn Offset.apply(value: Int) Int:
    return value + self.delta

fn adjusted(value: Int, operation: Increment) Int:
    return operation.apply(value)

fn main() Unit:
    print(adjusted(10, Offset(2)))
```

```text
12
```

`adjusted` knows the operation it can call. `Offset` supplies it with an ordinary method, and another type can supply a different one without changing `adjusted`.

## Methods

A type's methods are declared beside it, never inside the `type`. A receiver method is `fn Type.name(...)`; one that changes `self` is `fn var Type.name(...)`. A generic type repeats its parameters, `fn Box[T].get() T`. `self` is an implicit binding of the receiver type in each method; it is not a parameter and cannot be redeclared. A method may declare [type parameters of its own](#generic-operations).

A method is declared in the module that declares its type, and travels with the type wherever the type is used. To add operations to another module's type, write a free function or a wrapper type. There is no inheritance and no default implementation. A free function `fn reset(counter: Counter)` is called `reset(counter)`, never `counter.reset()`.

A type has one method per name. A second method of the same name on one receiver is an error, so one `close` or one `read` serves every interface that asks for it.

A receiver may add bounds, `fn Box[T: Equal].same(other: T) Bool`, so the method exists only where the arguments satisfy them, or fix an argument, `fn List[Int].sum() Int`. Methods of one name on receivers with different bounds or arguments are separate declarations; a call picks the one whose receiver matches.

A method may add [defaults](../functions/declarations-and-calls.md#default-arguments) to its parameters. A call on the concrete receiver uses them; a call through an interface value uses the interface signature, which carries the interface's own defaults.

## Satisfying an interface

A type satisfies an interface when each operation has one own method with the same name, parameter labels, `var`-ness, parameter types and result type. Nothing is declared: the methods are the declaration. After substituting generic arguments the methods must match the interface exactly: every operation once, under the same labels, order, types and result. An operation that changes its receiver is `var fn` in the interface and `fn var Type.name` on the type, though a method that does not change `self` also meets it. A `var` parameter is the same: an operation that changes a caller's value declares it `var` in both, and a call marks the argument `var` as for any [function](../functions/function-values-and-closures.md). Interface implementations preserve argument labels even though labels are not part of [function-value type identity](../functions/function-values-and-closures.md#function-type-compatibility).

<!-- manuscript-example: {"mode":"run","stdout":"3\n"} -->
```manuscript
interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

fn Offset.apply(value: Int) Int:
    return value + self.delta

fn adjusted(value: Int, operation: Increment) Int:
    return operation.apply(value)

fn main() Unit:
    print(adjusted(1, Offset(2)))
```

```text
3
```

- A mismatch is not an error until the type is used as the interface; the diagnostic lists the first operation that is missing or differs.
- A type with `fn var close() Unit!` satisfies `Closeable` and is closed at scope end, so a type that is also a `Source` and a `Sink` closes once. Make such a `close` safe to call again when an owner also closes the value.
- `Comparable`, `Equal`, `Hashable` and `JsonEncode` are met by an own `compare`, `equals`, `hash` or `to_json` of the exact signature. `Clonable`, `Data` and `Copy` are properties the compiler derives from a type's fields; they are not declared.
- Operations with type parameters of their own are met by a method that repeats them with the same bounds ([generic operations](#generic-operations)).

```text
// Rejected: amount does not match the interface's value label.
fn Offset.apply(amount: Int) Int:
    return amount + self.delta
```

## Coherence and visibility

A method is available wherever its type is used, and satisfying an interface follows from the methods, so it is the same in every module. There are no per-module extensions: a module cannot add methods to a type it imports, and a `Map` or `Set` always uses its key type's own `equals` and `hash`, or structural equality when it has none.

- Receivers must be source-defined types or enums declared in the same module. The standard library gives its own types and the built-in scalars their methods the same way.
- Interfaces may be generic but have at least one operation and no fields, cases, default bodies, associated types, or static operations.
- Exported interfaces expose every operation, under the [public surface rules](named-types.md#public-data-surfaces).
- A type exports its methods by being exported; a method is never exported by itself.

## Generic receivers

A receiver names its declaration's generic parameters; matching the receiver determines every argument.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
interface ReadValue[T]:
    fn get() T

type Box[T: Clonable]:
    value: T

fn Box[T].get() T:
    return self.value.clone()
```

This covers `Box[Int]`, `Box[String]`, and every other well-formed application. Bounds are inherited from the receiver declaration and from any bound written on the receiver. The body is checked once under them with `self: Box[T]`, and they must prove every nested application and operation legal. At a use, the matched arguments must satisfy them.

A bound written on the receiver restricts one method without restricting the data type:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
interface SameValue[T: Equal]:
    fn same(other: T) Bool

type Box[T]:
    value: T

fn Box[T: Equal].same(other: T) Bool:
    return self.value == other
```

A `Box[T]` without `T: Equal` has no `same`. A receiver may also fix an argument, `fn Box[Int].total() Int`; it applies to `Box[Int]` only. Two receiver forms that could match the same application and declare one name are rejected, as are two methods of one name on the same form.

## Generic operations

An interface operation and a method may declare type parameters after their name. The method repeats the operation's parameters in the same order with the same bounds, and its signature must match once they are renamed.

```text
interface Ranked[T]:
    fn best_by[K: Comparable](key: fn(T) K) T?

fn Scores.best_by[K: Comparable](key: fn(Int) K) Int?:
    ...
```

A call infers the operation's parameters from its arguments, or takes them explicitly: `scores.best_by[Int](key)`. Dispatch is static and each use is monomorphized, so the operation works on a concrete receiver and through a type parameter bounded by the interface. An interface with a generic operation cannot be the type of a value, because a method table has no entry for an operation whose types are not yet known; converting to it is rejected. The standard `List` uses this for `max_by` and `min_by` (`stdlib/collections/collections.ms`).

## Interface conversion

A value whose type satisfies an interface converts implicitly wherever that interface is expected: arguments, `:=` with a type annotation, fields, collection entries, and returns. The type's own methods [match every operation](#satisfying-an-interface); a method name alone never converts. Existing views of the same application are identity, and other interface-to-interface conversions and unchecked downcasts are rejected; a [contract type match](../control-flow/pattern-matching.md#contract-type-patterns) can recover the concrete receiver by runtime nominal check.

The conversion follows the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) of its position: a read-only argument borrows the operand, so it stays usable afterwards, while a stored position (field, collection entry, `:=`, return) moves it at its last use or needs `.clone()` otherwise. A borrowed operand becomes a view: the interface value points at the operand without copying it, and the operand stays unchangeable while the view is used ([references](references.md#borrowing)). Only an interface with a `var fn` operation copies a borrowed operand, since a call through it may change the value.

```manuscript
fn use_increment(operation: Increment) Int:
    return operation.apply(1)

offset := Offset(2)
result := use_increment(offset)
again := offset.delta
kept: Increment := offset.clone()
```

An interface is never constructed: `Increment(value: offset)` is rejected, so annotate the binding (`view: Increment = offset`) when no interface is otherwise expected. Generic inference does not convert: a type variable bound to `Offset` does not match `Increment` ([matching](generics.md#inference-from-arguments)).

### Selecting an operation

A type has one method per name, so a call on a concrete receiver, a generic parameter or an interface value names one operation. Interfaces that declare the same name and signature are met by that one method. A bound method keeps its receiver and has the operation's ordinary function type.

An interface type satisfies its own exact generic bound: `Converter[Int]` satisfies `T: Converter[Int]`, not `T: Converter[String]`.

```manuscript
fn invoke[T: Increment](operation: T) Int:
    view: Increment := operation
    return view.apply(1)

from_concrete := invoke(offset)
from_view := invoke(view)
```

Both calls satisfy the bound without implicit conversion.

## Interfaces and services

Pass a service as an interface value when a function needs storage, networking, or a clock. Contracts also serve as [generic bounds](generics.md) naming the operations a type argument must provide.
