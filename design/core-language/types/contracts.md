+++
title = "Operation contracts"
weight = 17
+++

# Operation contracts

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

An operation contract declares behavior that an implementation must supply. Use it at a boundary where a caller needs a set of operations without depending on one concrete data type.

The following contract refers to application-defined `Money`, `Receipt`, and `PaymentError` types:

```text
type Payments:
    fn charge(amount: Money) -> Result[Receipt, PaymentError]
```

The caller can see the amount accepted, the receipt returned on success, and the expected payment error. The contract uses the same explicit [function signature](../functions/declarations-and-calls.md) rules as an ordinary declaration.

## Explicit implementations

Operation contracts support explicit implementations through `impl Contract for DataType`; implementations bind `self` to the receiver. Contracts have no inheritance or default implementations.

An implementation supplies the contract's operations for the named data type. The implementation relationship is declared explicitly rather than inferred from coincidentally similar operation names.

```text
type Increment:
    fn apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) -> Int:
        return value + self.delta
```

`self` is an implicit receiver binding inside each implementation method, with the concrete receiver type. It is not written as a parameter, is not supplied as a call argument, and cannot be redeclared. The receiver does not add a field to the contract. Methods follow the ordinary immutable-field and reference rules.

Each operation is implemented exactly once, with the same operation name, parameter labels in the same declaration order, parameter types, and result type after substituting contract type arguments. Parameter labels/order are part of [function identity](../functions/function-values-and-closures.md#function-type-compatibility). Missing, extra, duplicate, or mismatched operations are compile errors. An implementation method cannot add defaults or its own type parameters.

```text
# Rejected: amount does not match the contract's value label.
impl Increment for Offset:
    fn apply(amount: Int) -> Int:
        return amount + self.delta
```

The rejected block is an alternative negative example, not a second block to add to the valid example.

## Coherence and visibility

An implementation is declared in the concrete type's defining module. It may implement an imported public contract, but cannot implement a contract for a type defined elsewhere. There is exactly one implementation for each concrete type and instantiated contract pair in a program. Duplicate implementations are rejected. Importing the concrete type loads its defining module and makes its implementations available; an unrelated module import cannot add methods retroactively.

Concrete and generic implementation blocks obey the same defining-module rule. Orphan implementations, blanket implementations for a bare type parameter, specialization, generic operations, and implementation inheritance are unsupported. Contracts can be generic but cannot have fields, cases, default bodies, associated types, or static operations. A contract declares at least one operation. An implementation does not re-export either its type or its contract.

Exported contracts expose every operation. Types in their operation signatures obey the [public surface rules](records.md#public-data-surfaces).

## Generic implementations

An implementation may declare type parameters immediately after `impl`. Its receiver must be an application of a nominal data declaration in the implementation's module. Every implementation parameter must occur in that receiver application, so matching the receiver determines all implementation arguments; parameters occurring only in the contract or method signatures are rejected.

```text
type ReadValue[T]:
    fn get() -> T

type Box[T]:
    value: T

impl[T] ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value
```

This block implements `ReadValue[Int]` for `Box[Int]`, `ReadValue[String]` for `Box[String]`, and every other well-formed application. Methods use the block's parameters but cannot declare their own. The compiler checks the body once under the declared bounds, with `self: Box[T]`, and checks exact substituted operation signatures. Implementation bounds must prove that every nested type application and operation in the body is legal. At a use, receiver matching supplies the arguments and those arguments must satisfy the block's bounds.

Bounds can restrict availability:

```text
type SameValue[T]:
    fn same(other: T) -> Bool

impl[T: Equal] SameValue[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other
```

A `Box[T]` with no proof of `T: Equal` cannot use this implementation. Bounds do not make the receiver shareable beyond the ordinary derivation for its fields.

Two blocks overlap if their receiver and contract applications can simultaneously match the same pair of types. Check this by structurally unifying both pairs, with each block's parameters treated as distinct variables and nominal identities and invariant arguments preserved. Ignore bounds in this check: different bounds cannot select competing implementations. Reject overlap at declaration checking, even if no current call uses it. There is no most-specific selection or specialization.

```text
# Rejected alongside the generic block above: both apply to Box[Int].
impl ReadValue[Int] for Box[Int]:
    fn get() -> Int:
        return self.value
```

Implementations of `ReadValue[Int]` and `ReadValue[String]` for the same receiver are distinct pairs, but their shared `get` name still requires an explicit view for dispatch. Generic method calls and specialized implementation dependencies obey the same [finite-application rules](generics.md#finite-recursive-applications) as generic functions.

## Explicit contract views

Concrete-to-contract conversion is explicit, written `Contract(value: concrete)`, or `Contract[T](value: concrete)` for a generic contract application. It succeeds at type checking only if that exact concrete type has an applicable declared implementation, including any implementation bounds. A method with the right spelling alone is insufficient. A plain contract view does not require or promise `Shareable`; it may retain a local nonshareable receiver. The wrapper retains the same concrete receiver reference; it does not copy native state or add resource-lifetime guarantees.

```text
fn use_increment(operation: Increment) -> Int:
    return operation.apply(value: 1)

let offset = Offset(delta: 2)
let view = Increment(value: offset)
let result = use_increment(operation: view)
# Rejected: conversion is not implicit at a call boundary.
let wrong = use_increment(operation: offset)
```

The plain constructor accepts an implementing concrete value or an existing plain/shared view of that exact contract application. An existing plain view is an identity conversion; a shared view loses only its static sharing guarantee. Different contracts/applications and contract-to-concrete downcasts are rejected.

Write generic view arguments explicitly or supply an expected application of the same contract, plain or shared. Operation names do not infer arguments, and an expected shared type cannot refine a plain constructor.

### Selecting an operation

A concrete receiver or generic parameter may call an operation directly when exactly one implemented/bounded contract supplies its name. Otherwise select a view, such as `Increment(value: offset).apply(value: 1)`. Arguments and result types cannot resolve operation-name ambiguity. A bound method retains its receiver and has the operation's ordinary function type.

A plain or shared contract type satisfies its own exact named generic bound without a source `impl`. For example, `Converter[Int]` satisfies `T: Converter[Int]`, but not `T: Converter[String]`. Generic disambiguation can therefore construct the same plain view whether `T` is concrete or already a view. A behavioral bound alone does not require sharing.

```text
fn invoke[T: Increment](operation: T) -> Int:
    return Increment(value: operation).apply(value: 1)

let from_concrete = invoke(operation: offset)
let from_view = invoke(operation: view)
```

Both calls satisfy the same bound; neither inserts an implicit conversion at the call boundary.

## Shared contract views

`Contract & Shareable`, including `Contract[T] & Shareable`, exposes the same contract operations with a statically safe receiver. It is the only value-type intersection. General intersections, Equal/Hashable refinements, and standalone Shareable value types are rejected.

Construct a shared view explicitly with `(Contract & Shareable)(value: receiver)`:

```text
let shared = (Increment & Shareable)(value: offset)
let same_shared = (Increment & Shareable)(value: shared)
let local = Increment(value: shared)  # Explicitly discard the sharing guarantee.
let operations: List[Increment & Shareable] = [shared]
# Rejected: local has only the plain Increment type.
let recovered = (Increment & Shareable)(value: local)
# Rejected: plain contract values do not satisfy the collection element bound.
let local_operations: List[Increment] = [local]
```

Shared construction requires both an implementation proof and a sharing proof:

| Receiver | Shared construction |
| --- | --- |
| Concrete shareable type implementing the exact contract | Accepted |
| Existing shared view of the exact contract application | Accepted as an identity view |
| Generic parameter bounded by the exact contract and Shareable | Accepted |
| Plain view, even with a safe hidden receiver | Rejected; the sharing proof is absent |

Plain and shared views are distinct types. Assignments, arguments, returns, and expected types never add or discard sharing implicitly. Both explicit constructors retain the same receiver and implementation; neither adds synchronization, equality, hashing, cleanup, or lifetime extension.

Shared views can be stored in collections and captured concurrently. Bound methods use the receiver's known sharing proof, then follow the separate [callable boundary rules](../../ownership-and-cleanup/values/sharing.md#function-values).

Only the receiver is guaranteed shareable. Parameters and results follow their own types: a shared service may return a nonshareable resource. Native adapters must prove receiver sharing before exposing a shared view.

## Contracts and external authority

A capability is passed as an explicit input when an operation needs external authority, such as storage or a payment service. [Modules and capabilities](../../modules-and-capabilities/modules/_index.md) describes effects, sharing requirements, and exported boundary contracts.

Contracts can also appear as [generic bounds](generics.md), where they name the operations required from a type argument.

[Previous: Equality and hashing](equality-and-hashing.md) · [Next: Generics and bounds](generics.md)
