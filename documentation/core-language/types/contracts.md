+++
title = "Interfaces and implementations"
weight = 7
+++

# Interfaces and implementations

An interface is an operation contract: implementations must supply the declared operations and signatures. Use it when callers should depend on behavior, not a data type. Signatures follow the ordinary [function rules](../functions/declarations-and-calls.md).

```manuscript
interface Payments:
    fn charge(amount: Money) Result[Receipt, PaymentError]
```

## Explicit implementations

Methods are written in `impl` blocks, never inside the `type`. `impl DataType:` declares the type's own methods and `impl Contract for DataType:` implements an interface; without `for` the one name is the type, with it the interface comes first. There is no inheritance and no default implementation. A free function `fn reset(counter: Counter)` is called `reset(counter)`, never `counter.reset()`; see the [counter example](../../learn/tour.md#behavior-on-types). The relationship is always declared, never inferred from matching names.

`impl DataType:` is accepted only in the module that declares the type; to add operations to another module's type, declare an interface and use a [local extension](#coherence-and-visibility). Several own-method blocks merge, and method names must be unique across them. The standard library declares its methods the same way. A method may declare [type parameters of its own](#generic-operations).

```manuscript
interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) Int:
        return value + self.delta
```

`self` is an implicit binding of the concrete receiver type in each method; it is not a parameter and cannot be redeclared.

After substituting generic arguments, an implementation must match the contract exactly: every operation once, with the same name, parameter labels, order, and types, and result type. Missing, extra, duplicate, or mismatched operations are compile errors; labels and order are part of [function identity](../functions/function-values-and-closures.md#function-type-compatibility). An operation that changes its receiver is `var fn` in the interface and in every impl; a mismatch in either direction is a compile error. A method may add [defaults](../functions/declarations-and-calls.md#default-arguments) for calls on the concrete receiver, but view calls use the interface signature. An operation may declare [type parameters of its own](#generic-operations); the implementation repeats them with the same bounds.

```manuscript
# Rejected: amount does not match the contract's value label.
impl Increment for Offset:
    fn apply(amount: Int) Int:
        return amount + self.delta
```

## Coherence and visibility

An implementation in the type's defining module is available wherever the type is used. One declared for an imported source type is a **local extension**, visible only in the declaring module. The interface may be local or imported. For example, `offset.ms` exports a record:

```text
export type Offset:
    delta: Int
```

Another module can add its own implementation:

```text
import Offset from "./offset.ms"

export interface Double:
    fn doubled() Int

impl Double for Offset:
    fn doubled() Int:
        return self.delta * 2

export fn double_view(value: Offset) Double:
    return value
```

Here `Offset(delta: 3).doubled()` returns `6`, but importing `double_view` or `Double` elsewhere does not add `doubled` to raw `Offset` values. `double_view(Offset(delta: 3)).doubled()` works anywhere because the returned interface value retains the implementation.

- Each module sees the defining module's implementations plus its own extensions. Duplicate or overlapping receiver/contract pairs in that set are rejected, including replacing a defining-module implementation.
- Separate modules may define the same local pair; extensions never propagate through imports.
- Views, bound methods, and specialized generics keep the implementation selected where they were created; a raw concrete value carries no extra conformance into another module.
- A `Map` or `Set` whose key type has a local `Equal` or `Hashable` keeps the implementations of the module that created it, including when another module adds, removes, or looks up keys; a collection created where the type has none keeps structural equality.
- Receivers must be source-defined nominal records or alternatives. Standard-library receivers, interfaces, bare type parameters, specialization, and implementation inheritance are unsupported.
- Contracts may be generic but have at least one operation and no fields, cases, default bodies, associated types, or static operations.
- Implementations re-export neither their type nor their contract. Exported contracts expose every operation, under the [public surface rules](records.md#public-data-surfaces).
- Same-named operations from different interfaces need an [interface-typed binding](#selecting-an-operation).

## Generic implementations

An implementation uses its receiver declaration's generic parameters; only those occurring in the receiver application are in scope, and matching the receiver determines every argument. Interface parameter substitution is positional. Undeclared names are rejected: `impl ReadValue[U] for Box[U]` fails when `Box` declares only `T`.

```manuscript
interface ReadValue[T]:
    fn get() ref T

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    fn get() ref T:
        return self.value
```

This covers `Box[Int]`, `Box[String]`, and every other well-formed application. Bounds are inherited from the receiver declaration and, for interface arguments that are receiver parameters, the interface declaration. The body is checked once under them with `self: Box[T]`, and they must prove every nested application and operation legal. At a use, the matched arguments must satisfy them; a concretely specialized parameter is substituted into other bounds (`Pair[A, B: ReadValue[A]]` with receiver `Pair[Int, B]` gives `B: ReadValue[Int]`).

Interface parameter bounds can restrict an implementation without restricting the data type:

```manuscript
interface SameValue[T: Equal]:
    fn same(other: T) Bool

impl SameValue[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other
```

A `Box[T]` without `T: Equal` cannot use this implementation.

Two blocks overlap if their receiver and contract applications can match the same pair, found by structural unification with distinct variables per block; bounds are ignored. Overlap among implementations visible in a module is rejected at declaration, used or not. There is no most-specific selection.

```manuscript
# Rejected alongside the generic block above: both apply to Box[Int].
impl ReadValue[Int] for Box[Int]:
    fn get() Int:
        return self.value
```

`ReadValue[Int]` and `ReadValue[String]` on one receiver are distinct pairs but share `get`, so dispatch needs an interface-typed binding. Specialization follows the [finite-application rules](generics.md#finite-recursive-applications).

## Generic operations

An interface operation, an implementation method and an inherent method may declare type parameters after their name. The implementation repeats the interface operation's parameters in the same order with the same bounds, and its signature must match once they are renamed.

```manuscript
interface Ranked[T]:
    fn best_by[K: Comparable](key: fn(T) K) Optional[T]

impl Ranked[Int] for Scores:
    fn best_by[K: Comparable](key: fn(Int) K) Optional[Int]:
        ...
```

A call infers the operation's parameters from its arguments, or takes them explicitly: `scores.best_by[Int](key)`. Dispatch is static and each use is monomorphized, so the operation works on a concrete receiver and through a type parameter bounded by the interface. An interface with a generic operation cannot be the type of a value, because a method table has no entry for an operation whose types are not yet known; converting to it is rejected. The standard `List` uses this for `max_by` and `min_by` (`stdlib/collections.ms`).

## Interface conversion

A value whose type has a declared implementation of an interface converts implicitly wherever that interface is expected: arguments, `let` with a type annotation, record fields, collection entries, and returns. The relationship is still declared (`impl Contract for Type`); matching method names never convert. Existing views of the same application are identity, and other interface-to-interface conversions and unchecked downcasts are rejected; a [contract type match](../control-flow/pattern-matching.md#contract-type-patterns) can recover the concrete receiver by runtime nominal check.

The conversion follows the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) of its position: a read-only argument borrows the operand, so it stays usable afterwards, while a stored position (record field, collection entry, `let`, return) moves it at its last use or needs `.clone()` otherwise. The interface value owns a copy when the operand is borrowed.

```manuscript
fn use_increment(operation: Increment) Int:
    return operation.apply(1)

let offset = Offset(2)
let result = use_increment(offset)
let again = offset.value
let kept: Increment = offset.clone()
```

An interface is never constructed: `Increment(value: offset)` is rejected, so annotate the binding (`let view: Increment = offset`) when no interface is otherwise expected. Generic inference does not convert: a type variable bound to `Offset` does not match `Increment` ([matching](generics.md#inference-from-arguments)).

### Selecting an operation

A receiver or generic parameter may call an operation directly when exactly one implemented or bounded contract supplies that name. Otherwise bind the value to one interface and call through it: `let view: Increment = offset` then `view.apply(value: 1)`; arguments and result types never disambiguate. A bound method keeps its receiver and has the operation's ordinary function type.

A contract type satisfies its own exact generic bound without an `impl`: `Converter[Int]` satisfies `T: Converter[Int]`, not `T: Converter[String]`.

```manuscript
fn invoke[T: Increment](operation: T) Int:
    let view: Increment = operation
    return view.apply(1)

let from_concrete = invoke(offset)
let from_view = invoke(view)
```

Both calls satisfy the bound without implicit conversion.

## Interfaces and services

Pass a service as an interface value when a function needs storage, networking, or a clock. Contracts also serve as [generic bounds](generics.md) naming the operations a type argument must provide.
