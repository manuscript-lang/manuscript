+++
title = "Operation contracts"
weight = 17
+++

# Operation contracts

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

An interface lists the operations a caller needs. This is an operation contract: a concrete implementation must supply those operations with the declared signatures. Use it when callers should depend on behavior rather than a particular data type.

The following contract refers to application-defined `Money`, `Receipt`, and `PaymentError` types:

```manuscript
interface Payments:
    fn charge(amount: Money) -> Result[Receipt, PaymentError]
```

The caller can see the amount accepted, the receipt returned on success, and the expected payment error. The contract uses the same explicit [function signature](../functions/declarations-and-calls.md) rules as an ordinary declaration.

## Explicit implementations

Operation contracts support explicit implementations through `impl Contract for DataType`; implementations bind `self` to the receiver. Contracts have no inheritance or default implementations.

An implementation supplies the contract's operations for the named data type. The implementation relationship is declared explicitly rather than inferred from coincidentally similar operation names.

```manuscript
interface Increment:
    fn apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) -> Int:
        return value + self.delta
```

`self` is an implicit receiver binding inside each implementation method, with the concrete receiver type. It is not written as a parameter, is not supplied as a call argument, and cannot be redeclared. The receiver does not add a field to the contract. Methods follow the ordinary immutable-field and reference rules.

An implementation must match the contract exactly. After substituting generic type arguments, check:

- every operation appears exactly once;
- operation names match;
- parameter labels, their declaration order, and parameter types match;
- result types match.

Missing, extra, duplicate, or mismatched operations are compile errors. An implementation method may add [defaults](../functions/declarations-and-calls.md#default-arguments) for calls through its concrete receiver; interface-view calls still require the interface signature's arguments. Neither interface operations nor methods declare their own generic parameters. Parameter labels and order are part of [function identity](../functions/function-values-and-closures.md#function-type-compatibility).

```manuscript
# Rejected: amount does not match the contract's value label.
impl Increment for Offset:
    fn apply(amount: Int) -> Int:
        return amount + self.delta
```

The rejected block is an alternative negative example, not a second block to add to the valid example.

## Coherence and visibility

An implementation declared in the concrete type's defining module is available wherever that type is used. An implementation declared for an imported source type is a **local extension**, visible only within the module declaring the implementation. The interface may be local or imported in either case. No new syntax is needed.

For example, `offset.ms` exports a record:

```text
export type Offset:
    delta: Int
```

Another module can add its own interface implementation:

```text
import Offset from "./offset.ms"

export interface Double:
    fn doubled() -> Int

impl Double for Offset:
    fn doubled() -> Int:
        return self.delta * 2

export fn double_view(value: Offset) -> Double:
    return Double(value: value)
```

Inside this module, `Offset(delta: 3).doubled()` returns `6`. Importing `double_view` or `Double` elsewhere does not make `doubled` available on raw `Offset` values. Calling `double_view(Offset(delta: 3)).doubled()` works there because the returned view retains the selected implementation.

Each module sees the receiver's defining-module implementations plus its own local extensions. Reject duplicate or overlapping receiver/contract pairs within that visible set, including attempts to replace a defining-module implementation. Separate modules may define the same local pair independently; neither extension becomes visible through imports, including transitive imports. Different interfaces with the same operation name still require an explicit view to disambiguate.

Views, bound methods, and specialized generic functions retain the implementation selected where they are created. A generic bound uses the implementation evidence supplied at specialization, including when forwarded to another generic function. Calls on statically concrete types inside a function use that function's declaring module. Passing a raw concrete value does not carry additional conformance into another module.

Concrete and generic blocks obey the same visibility rules. Receivers must be source-defined nominal records or alternatives; intrinsic and standard-library receivers, interfaces, bare type parameters, specialization, generic operations, and implementation inheritance remain unsupported. Contracts can be generic but cannot have fields, cases, default bodies, associated types, or static operations. A contract declares at least one operation. An implementation does not re-export either its type or its contract.

Exported contracts expose every operation. Types in their operation signatures obey the [public surface rules](records.md#public-data-surfaces).

## Generic implementations

An implementation uses generic parameters from its receiver type declaration. Its receiver must be an application of a local or imported source nominal data declaration. Parameter names in the receiver application come from that data declaration. Inherited bounds retain their original nominal identities; an extending module need not import the names used in those bounds. Only parameters occurring in the receiver application are in scope for the interface and methods; matching the receiver determines all implementation arguments. Concrete and nested receiver applications remain supported. Interface parameter names need not match data parameter names: an application substitutes the receiver parameters positionally. An undeclared name such as `U` in `impl ReadValue[U] for Box[U]` is rejected when `Box` declares only `T`.

```manuscript
interface ReadValue[T]:
    fn get() -> T

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value
```

This block implements `ReadValue[Int]` for `Box[Int]`, `ReadValue[String]` for `Box[String]`, and every other well-formed application. Methods use the receiver declaration's parameters but cannot declare their own. Bounds are inherited from the receiver type declaration and, for interface arguments that are receiver parameters, from the interface declaration. The compiler checks the body once under these inherited bounds, with `self: Box[T]`, and checks exact substituted operation signatures.

Inherited bounds must prove that every nested type application and operation in the body is legal. At a use, receiver matching supplies the arguments and those arguments must satisfy the inherited bounds. When a receiver argument is specialized to a concrete type, references to that parameter in other inherited bounds use the concrete type. For example, `Pair[A, B: ReadValue[A]]` with receiver `Pair[Int, B]` gives `B: ReadValue[Int]`.

Interface parameter bounds can restrict implementation availability without restricting the data type:

```manuscript
interface SameValue[T: Equal]:
    fn same(other: T) -> Bool

impl SameValue[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other
```

A `Box[T]` with no proof of `T: Equal` cannot use this implementation. Receiver references may be passed freely; equality remains a separate property.

Two blocks overlap if their receiver and contract applications can simultaneously match the same pair of types. Check this by structurally unifying both pairs, with each receiver's inherited parameters treated as distinct variables and nominal identities and invariant arguments preserved. Ignore bounds in this check: different bounds cannot select competing implementations. Reject overlap between implementations visible in the same module at declaration checking, even if no current call uses it. There is no most-specific selection or specialization.

```manuscript
# Rejected alongside the generic block above: both apply to Box[Int].
impl ReadValue[Int] for Box[Int]:
    fn get() -> Int:
        return self.value
```

Implementations of `ReadValue[Int]` and `ReadValue[String]` for the same receiver are distinct pairs, but their shared `get` name still requires an explicit view for dispatch. Generic method calls and specialized implementation dependencies obey the same [finite-application rules](generics.md#finite-recursive-applications) as generic functions.

## Explicit contract views

Create a contract view explicitly with `Contract(value: concrete)`. For a generic contract, use `Contract[T](value: concrete)`. The concrete type must have an applicable declared implementation and satisfy its bounds; a matching method name alone is not enough.

A view keeps the same receiver reference without copying native state or extending its resource lifetime. The receiver retains its concurrency contract: passing a view does not add a lock to a local mutable collection.

```manuscript
fn use_increment(operation: Increment) -> Int:
    return operation.apply(value: 1)

let offset = Offset(delta: 2)
let view = Increment(value: offset)
let result = use_increment(operation: view)
# Rejected: conversion is not implicit at a call boundary.
let wrong = use_increment(operation: offset)
```

The constructor accepts an implementing concrete value or an existing view of the exact contract application. An existing view is an identity conversion. Different contracts/applications and contract-to-concrete downcasts are rejected.

Write generic view arguments explicitly or supply an expected application of the same contract. Operation names do not infer arguments.

### Selecting an operation

A concrete receiver or generic parameter may call an operation directly when exactly one implemented/bounded contract supplies its name. Otherwise select a view, such as `Increment(value: offset).apply(value: 1)`. Arguments and result types cannot resolve operation-name ambiguity. A bound method retains its receiver and has the operation's ordinary function type.

A contract type satisfies its own exact named generic bound without a source `impl`. For example, `Converter[Int]` satisfies `T: Converter[Int]`, but not `T: Converter[String]`. All such values may be passed between operations.

```manuscript
fn invoke[T: Increment](operation: T) -> Int:
    return Increment(value: operation).apply(value: 1)

let from_concrete = invoke(operation: offset)
let from_view = invoke(operation: view)
```

Both calls satisfy the same bound; neither inserts an implicit conversion at the call boundary.

## Concurrent use

All contract values may be passed between operations; concurrent invocation follows the receiver's contract. There is one view type, with ordinary spelling such as `ReadValue[Int]`. Explicit view construction checks the implementation relationship and preserves the receiver reference. No conversion adds synchronization, equality, hashing, cleanup, or lifetime extension. Native services synchronize their internals and lifecycle. Source implementations that need a local mutable queue across concurrent calls keep it behind Synchronized.

## Contracts and external authority

A capability is passed as an explicit input when an operation needs external authority, such as storage or a payment service. [Modules and capabilities](../../modules-and-capabilities/modules/_index.md) describes effects, native synchronization obligations, and exported boundary contracts.

Contracts can also appear as [generic bounds](generics.md), where they name the operations required from a type argument.

[Previous: Equality and hashing](equality-and-hashing.md) · [Next: Generics and bounds](generics.md)
