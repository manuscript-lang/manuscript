+++
title = "Records and nominal types"
weight = 12
+++

# Records and nominal types

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A record is a nominal type with named, immutable fields. Use it to give domain data an explicit shape.

```text
type Customer:
    name: String
    email: Optional[String]
```

Records have nominal identity and immutable fields. A resource field retains an ordinary reference to that object.

A record declaration has at least one field; an empty body is not a record declaration. Field types are explicit. Duplicate field names and field default initializers are compile errors.

## Construction

Constructors supply every field by name exactly once. Missing, duplicate, or unknown fields are compile errors. Call order may differ from declaration order; field expressions evaluate in written call order. Each expression is checked against its declared field type, including expected-type checking for `none` and empty lists.

```text
let customer = Customer(name: "Ada", email: none)
let name = customer.name
```

The constructor states which value belongs to each field. `customer.name` reads the field. To use the optional email, handle its alternatives as described in [optional values](optionals.md).

```text
# Rejected: required email is missing.
let incomplete = Customer(name: "Ada")
# Rejected: fields are immutable.
customer.name = "Grace"
```

Generic records use explicit parameters, such as `type Box[T]:` with `value: T`. `Box[Int](value: 1)` constructs that application; see [generics](generics.md).

## Domain identity

Distinct identifiers such as `CustomerId` use nominal field types.

```text
type CustomerId:
    value: String

type OrderId:
    value: String
```

The two declarations represent distinct types even though their fields have the same shape. This keeps a customer identifier distinct from an order identifier at function boundaries.

```text
let customer_id = CustomerId(value: "42")
# Rejected: equal field shapes do not make nominal types interchangeable.
let order_id: OrderId = customer_id
```

A nominal identity includes its defining module, declaration, and type arguments. Alternate normalized import paths to the same module do not create new types. Type applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a record exports its constructor and every field. Field visibility modifiers and opaque exports are unsupported. Field types must satisfy [public signature closure](../../modules-and-capabilities/modules/declarations.md#public-signature-closure), including types nested inside Optional or collections. Importing a record does not import the names of its field types.

## Recursive data

Direct or mutually recursive inline record/alternative layouts are rejected. Build a layout dependency graph using only types stored inline in record fields and alternative payloads. `Optional` and `Result` are inline alternatives, so their stored payload types remain inline dependencies. Immutable `List`, `Map`, and `Set` storage is indirect; removing those container storage edges must leave an acyclic inline graph.

Function values and contract values also have indirect representations. Function parameter/result types and contract operation signatures are not inline storage edges and do not introduce a concrete layout cycle merely by mentioning the enclosing type. Generic recursive references still satisfy the separate finite-application rule in [generics](generics.md#finite-recursive-applications).

```text
type Node:
    value: Int
    children: List[Node]

type BadNode:
    next: Optional[BadNode]  # Rejected: inline recursion.

type DeferredNode:
    build: fn() -> DeferredNode  # Allowed: function value is indirect.
```

Container element/key bounds still apply. A `Set[Node]` does not become valid just because it guards recursion: its element must be hashable. Generic recursive cycles must preserve the same type parameters; expanding recursion such as `Grow[T]` containing `List[Grow[List[T]]]` is rejected. See [generic well-formedness](generics.md) and [structural equality](equality-and-hashing.md).

## Resource fields

A record containing a resource does not implicitly close it or extend its open lifetime. Cleanup follows explicit [resource scopes](../../ownership-and-cleanup/cleanup/scopes.md). Immutable fields do not make the referenced native service immutable; sharing eligibility depends on its implementation.

A `type` declaration uses one form. Use [alternatives](alternatives.md) for a choice among cases and [operation contracts](contracts.md) for required behavior.

[Previous: Strings and bytes](../basics/text-and-bytes.md) · [Next: Alternatives](alternatives.md)
