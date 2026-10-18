+++
title = "Records and nominal types"
weight = 1
+++

# Records and nominal types

A record groups named fields into one value. Fields are mutable, assignment and argument passing share the same instance (use `.clone()` for a copy), and each declaration is a distinct nominal type.

```manuscript
type Customer:
    name: String
    email: Optional[String]
```

Field types are explicit and names unique. An empty record is `type Marker:`. A field may have a default expression checked against its type.

## Construction

Supply each required field exactly once, by position or label; fields with defaults may be omitted. Missing, duplicate, and unknown fields are compile errors. Supplied expressions evaluate in written order, then omitted defaults in declaration order. Each is checked against its field type, so `none` and `[]` get their expected type.

```manuscript
let customer = Customer(name: "Ada", email: none)
let name = customer.name
```

Positional arguments follow declaration order and labels are optional under the [call rules](../functions/declarations-and-calls.md#argument-names): `Box(3)` equals `Box(value: 3)`. Handle an optional field as described in [optional values](optionals.md).

```manuscript
# Rejected: required email is missing.
let incomplete = Customer(name: "Ada")
# Accepted: let fixes the binding, not the record fields.
customer.name = "Grace"
```

Generic records declare parameters (`type Box[T]:`) and construct as `Box[Int](value: 1)`; see [generics](generics.md).

```manuscript
type Options:
    count: Int = 3
    total: Int = count + 1

let options = Options(count: 5)  # total defaults to 6
```

A default may use earlier fields and module declarations, but not itself or later fields. It is evaluated on each construction, so collection defaults are fresh. Any supplied value, even `unit`, `none`, or zero, skips the default. Generic arguments never come from defaults.

## Mutation and cloning

Methods come from `impl Type:` or `impl Interface for Type:` ([explicit implementations](contracts.md#explicit-implementations)); methods inside the record are rejected. A method can update receiver fields in place:

```manuscript
interface Counter:
    fn increment() -> Unit

type Val:
    val: Int

impl Counter for Val:
    fn increment() -> Unit:
        self.val = self.val + 1
```

Field writes keep the declared type; the receiver evaluates once, before the new value. Parameters, aliases, nested fields, and closure captures share the same storage.

`.clone()` is shallow: it copies field storage and keeps nested records, collections, callbacks, and resource references. Changing a clone's own field leaves the original alone; changing a shared nested object affects both.

Records, alternatives, `List`, `Map`, `Set`, and `Bytes` have `.clone()`. Files, sockets, queues, synchronization objects, guards, and other service handles do not; a cloned record keeps the same handle.

## Domain identity

Wrap identifiers in their own records so they cannot be mixed up.

```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String
```

```manuscript
let customer_id = CustomerId("42")
# Rejected: equal field shapes do not make nominal types interchangeable.
let order_id: OrderId = customer_id
```

Identity is module, declaration, and type arguments; alternate import paths to one module do not create new types. Applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a record exports its constructor and every field; there are no field visibility modifiers or opaque exports. Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including nested types. Importing a record does not import its field types' names.

## Recursive data

Records and alternatives may refer to themselves or each other directly, with no box. Give construction an endpoint with a base case, `Optional`, or a collection.

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
    let expr = Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
```

A linked record ends with an absent successor; mutation can later form a cycle:

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

Constructors still need every required field, and a binding is unavailable in its own initializer, so `let node = Node(value: 1, next: node)` is rejected. `.clone()` keeps recursive references. Recursive shapes derive no `Hashable`; keys need explicit implementations ([equality and hashing](equality-and-hashing.md)).

Generic recursion must preserve type parameters along every cycle; see [finite recursive applications](generics.md#finite-recursive-applications).

## Resource fields

A record holding a resource neither closes it nor extends its lifetime; cleanup follows [resource scopes](../cleanup/scopes.md). Copying does not duplicate native services.

Use [alternatives](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md).
