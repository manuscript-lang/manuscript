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

Constructors supply each required field exactly once, positionally or by label, and may omit fields with defaults. Missing required fields, duplicate fields, and unknown fields are compile errors. Call order may differ from declaration order; supplied expressions evaluate in written call order, followed by omitted defaults in field declaration order. Each expression is checked against its declared field type, including expected-type checking for `none` and empty lists.

```manuscript
let customer = Customer(name: "Ada", email: none)
let name = customer.name
```

Constructor arguments follow field declaration order and accept optional labels under the ordinary [call rules](../functions/declarations-and-calls.md#argument-names). `Box(3)` and `Box(value: 3)` are equivalent; multi-field records also accept positional and mixed arguments. `customer.name` reads the field. To use the optional email, handle its alternatives as described in [optional values](optionals.md).

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

A method declared through an [interface implementation](contracts.md#explicit-implementations) can update its receiver's fields without replacing the record. User-defined methods require `impl Interface for Type:`; `impl Type:` and method declarations inside a source record are unsupported:

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

Records and alternatives may refer directly to themselves or to each other. Their fields retain references to existing values; recursive payloads do not need a collection or an explicit box. Use a base case, `Optional`, or a collection when construction needs an endpoint.

This alternative represents binary addition directly:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)

fn evaluate(expr: Expr) -> Int:
    match expr:
        Num(value): return value
        Add(left, right): return evaluate(left) + evaluate(right)

test "recursive expression":
    let expr = Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
```

For a linked record, an absent successor provides the endpoint. After construction, ordinary mutation can connect existing values into a cycle:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

type Node:
    value: Int
    next: Optional[Node]

test "recursive links":
    let node = Node(value: 1, next: none)
    node.next = some(node)
    let copy = node.clone()
    copy.next.unwrap().value = 2
    if node.value != 2 or copy.value != 1:
        panic("cloning must retain nested references")
```

Every constructor still supplies all required fields. A binding is unavailable in its own initializer, so `let node = Node(value: 1, next: node)` is rejected. A declaration with only required recursive fields is permitted, but does not gain an implicit empty or partially initialized value. Use a terminating case or `Optional` when building finite values.

Aliases observe field mutations, and `.clone()` copies only the outer storage, retaining recursive references. Structural equality terminates on cyclic data. Recursive shapes do not derive `Hashable` automatically; map keys and set elements need explicit, consistent `Equal` and `Hashable` implementations. See [equality and hashing](equality-and-hashing.md).

Generic recursion must preserve its type parameters along every cycle, including references through collections, function signatures, and interfaces. See [finite recursive applications](generics.md#finite-recursive-applications).

## Resource fields

A record containing a resource does not implicitly close it or extend its open lifetime. Cleanup follows explicit [resource scopes](../cleanup/scopes.md). Copying a record does not duplicate a referenced native service; each service synchronizes its own state and lifecycle.

A `type` declaration uses fields or cases. Use [alternatives](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md) that declare required behavior.
