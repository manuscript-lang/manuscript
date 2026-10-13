+++
title = "Records and nominal types"
weight = 1
+++

# Records and nominal types

A record groups named fields into one value. Its fields can be changed after construction. Assignment and argument passing retain the same instance; use `.clone()` when you need a separate copy. Each record declaration creates a distinct type; this is called nominal typing. Use a record when data has a known shape, such as a customer with a name and email.

```manuscript
type Customer:
    name: String
    email: Optional[String]
```

Records have nominal identity and mutable fields. A resource field retains an ordinary reference to that object.

A record declaration may have an empty schema, written as `type Marker:` followed by a newline. Field types are explicit. Duplicate field names are compile errors. A field may have a default expression checked against its declared type.

## Construction

Constructors supply required fields by name exactly once and may omit fields with defaults. Missing required fields, duplicate fields, and unknown fields are compile errors. Call order may differ from declaration order; supplied expressions evaluate in written call order, followed by omitted defaults in field declaration order. Each expression is checked against its declared field type, including expected-type checking for `none` and empty lists.

```manuscript
let customer = Customer(name: "Ada", email: none)
let name = customer.name
```

The constructor states which value belongs to each field. For exactly one declared field, its label may be omitted: `Box(3)` and `Box(value: 3)` are equivalent. Multi-field records require labels even when defaults leave only one supplied argument. `customer.name` reads the field. To use the optional email, handle its alternatives as described in [optional values](optionals.md).

```manuscript
# Rejected: required email is missing.
let incomplete = Customer(name: "Ada")
# Accepted: let fixes the binding, not the record fields.
customer.name = "Grace"
```

Generic records use explicit parameters, such as `type Box[T]:` with `value: T`. `Box[Int](value: 1)` constructs that application; see [generics](generics.md).

```manuscript
type Options:
    count: Int = 3
    total: Int = count + 1

let options = Options(count: 5)  # total defaults to 6
```

A default can refer to earlier fields and module declarations, including functions; it cannot refer to itself or a later field. Defaults evaluate anew on each construction, so collection defaults have fresh storage. Supplying a value, including `unit`, `none`, or zero, skips that field's default. Generic arguments come from supplied fields, explicit type arguments, or the expected type, rather than from defaults.

## Mutation and cloning

A method can update its receiver's fields without replacing the record:

```manuscript
interface Counter:
    fn increment() -> Unit

type Val:
    val: Int

impl Counter for Val:
    fn increment() -> Unit:
        self.val = self.val + 1
```

Field writes keep the declared field type. The receiver expression is evaluated once, before the replacement value. Nested fields, parameters, aliases, and closure captures refer to the same record storage.

`.clone()` returns a new record with independent field storage. It is shallow: nested records, collections, callbacks, and resource references are retained. Changing a clone's own field does not change the original; changing a shared nested object affects both.

Record and alternative values and `List`, `Map`, `Set`, and `Bytes` expose a built-in `.clone()`. Native file handles, sockets, queues, synchronization objects, guards, and other service handles do not. A record containing a handle can be cloned, but that keeps the same handle and its existing lifetime.

## Domain identity

Distinct identifiers such as `CustomerId` use nominal field types.

```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String
```

The two declarations represent distinct types even though their fields have the same shape. This keeps a customer identifier distinct from an order identifier at function boundaries.

```manuscript
let customer_id = CustomerId(value: "42")
# Rejected: equal field shapes do not make nominal types interchangeable.
let order_id: OrderId = customer_id
```

A nominal identity includes its defining module, declaration, and type arguments. Alternate normalized import paths to the same module do not create new types. Type applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a record exports its constructor and every field. Field visibility modifiers and opaque exports are unsupported. Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including types nested inside Optional or collections. Importing a record does not import the names of its field types.

## Recursive data

Direct or mutually recursive inline record/alternative layouts are rejected. Build a layout dependency graph using only types stored inline in record fields and alternative payloads. `Optional` and `Result` are inline alternatives, so their stored payload types remain inline dependencies. `List`, `Map`, and `Set` storage is indirect; removing those container storage edges must leave an acyclic inline graph.

Function values and contract values also have indirect representations. Function parameter/result types and contract operation signatures are not inline storage edges and do not introduce a concrete layout cycle merely by mentioning the enclosing type. Generic recursive references still satisfy the separate finite-application rule in [generics](generics.md#finite-recursive-applications).

```manuscript
type Node:
    value: Int
    children: List[Node]

type BadNode:
    next: Optional[BadNode]  # Rejected: inline recursion.

type DeferredNode:
    build: fn() -> DeferredNode  # Allowed: function value is indirect.
```

For recursive alternatives, put recursive children in a collection. This expression tree uses a sum of any number of terms, so its `List[Expr]` payload expresses the intended arity:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import List from "@std/collections.ms"
import panic from "@std/faults.ms"

type Expr:
    case Num(value: Int)
    case Sum(terms: List[Expr])

fn evaluate(expr: Expr) -> Int:
    match expr:
        Num(value):
            return value
        Sum(terms):
            var total = 0
            for term in terms:
                total = total + evaluate(term)
            return total

test "recursive expression":
    let expr = Expr.Sum([Expr.Num(1), Expr.Sum([Expr.Num(2), Expr.Num(3)])])
    if evaluate(expr) != 6:
        panic("unexpected expression value")
```

A fixed binary payload such as `Add(left: Expr, right: Expr)` is rejected by the same inline-layout rule. Using `operands: List[Expr]` is supported, but does not enforce a length of two; validate that invariant when constructing or consuming the value. Wrapping the recursive field in `Optional` does not break the cycle.

Container element/key bounds still apply. A `Set[Node]` does not become valid just because it guards recursion: its element must be hashable. Generic recursive cycles must preserve the same type parameters; expanding recursion such as `Grow[T]` containing `List[Grow[List[T]]]` is rejected. See [generic well-formedness](generics.md) and [structural equality](equality-and-hashing.md).

## Resource fields

A record containing a resource does not implicitly close it or extend its open lifetime. Cleanup follows explicit [resource scopes](../cleanup/scopes.md). Copying a record does not duplicate a referenced native service; each service synchronizes its own state and lifecycle.

A `type` declaration uses fields or cases. Use [alternatives](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md) that declare required behavior.
