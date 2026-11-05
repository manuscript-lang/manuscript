+++
title = "Records and nominal types"
weight = 1
+++

# Records and nominal types

A record groups related data into named fields. Use it when a function should receive one meaningful value, such as a customer or an order. Each declaration creates a distinct type; fields change through a `var` binding.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\ntrue\n"} -->
```manuscript
type Customer:
    name: String
    email: String?

export fn main() Int:
    let customer = Customer("Ada")
    print(customer.name)
    print(customer.email.is_none())
    return 0
```

```text
Ada
true
```

Field types are explicit and names unique. An empty record is `type Marker:`. A field may have a default expression checked against its type.

## Construction

Supply each required field exactly once, by position or label; fields with defaults may be omitted. Missing, duplicate, and unknown fields are compile errors. Supplied expressions evaluate in written order, then omitted defaults in declaration order. Each is checked against its field type, so `none` and `[]` get their expected type.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\n"} -->
```manuscript
type Customer:
    name: String
    email: String?

export fn main() Int:
    let customer = Customer(name: "Ada", email: none)
    let name = customer.name
    print(name)
    return 0
```

```text
Ada
```

Positional arguments follow declaration order and labels are optional under the [call rules](../functions/declarations-and-calls.md#argument-names): `Box(3)` equals `Box(value: 3)`. Handle an optional field as described in [optional values](optionals.md).

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":"cannot change `customer.name`: `customer` is declared with let"} -->
```manuscript
type Customer:
    name: String
    email: String?

// An omitted optional field is none.

export fn main() Int:
    let customer = Customer("Ada")
    let without_email = Customer(name: "Ada")
    // Rejected: changing a field requires a var binding.
    customer.name = "Grace"
    return 0
```

The diagnostic explains that `customer.name` cannot change because `customer` was declared with `let`.

Generic records declare parameters (`type Box[T]:`) and construct as `Box[Int](value: 1)`; see [generics](generics.md).

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"5\n6\n"} -->
```manuscript
type Options:
    count: Int = 3
    total: Int = count + 1

export fn main() Int:
    let options = Options(count: 5)  // total defaults to 6
    print(options.count)
    print(options.total)
    return 0
```

```text
5
6
```

An optional field with no explicit default is `none` when omitted. A default may use earlier fields and module declarations, but not itself or later fields. It is evaluated on each construction, so collection defaults are fresh. Any supplied value, even `unit`, `none`, or zero, skips the default. Generic arguments never come from defaults.

## Mutation and cloning

A clone gives a value its own nested data. Changing the clone leaves the original alone.

Save as `customers.ms` and run `ms run customers.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\nGrace\n","filename":"customers.ms"} -->
```manuscript
type Customer:
    name: String
    email: String?

export fn main() Int:
    let original = Customer("Ada")
    var updated = original.clone()
    updated.name = "Grace"
    print(original.name)
    print(updated.name)
    return 0
```

```text
Ada
Grace
```

Methods come from `impl Type:` or `impl Interface for Type:` ([explicit implementations](contracts.md#explicit-implementations)); methods inside the record are rejected. A method marked `var fn` can update receiver fields in place:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"1\n"} -->
```manuscript
interface Counter:
    var fn increment() Unit

type Val:
    val: Int

impl Counter for Val:
    var fn increment() Unit:
        self.val = self.val + 1

export fn main() Int:
    var value = Val(0)
    value.increment()
    print(value.val)
    return 0
```

```text
1
```

Field writes keep the declared type; the receiver evaluates once, before the new value. Records follow the move and borrow rules of every container; only primitives copy implicitly. Closures borrow or own their captures. A function changes its caller's value through a `var` parameter.

For clonable data, `.clone()` is a deep copy of nested records and collections; changing the copy never affects the original. Resources are not copied implicitly and do not satisfy the generic `Clonable` bound.

Records, enums, `List`, `Map`, `Set`, and `Bytes` support data cloning when their contents permit it. Owned collections such as `Queue` can also be cloned when their element type is clonable. A function value has no clone: it owns its captures and has one owner. A record, enum, or collection holding a resource or a function value is not `Clonable`, so generic copying operations (`concat`, `take`, `sorted`) do not apply to it; move it, or build it again (a `Router` is moved into `mount` and into its `handler`).

An API can separately offer explicit resource duplication. `FileHandle.clone()` returns `FileHandle!`: it duplicates an operating-system descriptor and can fail. The new handle closes independently, but shares the original file position; this is not an independent copy of the file or generic data cloning. See [cloning a resource](../cleanup/closeable.md#cloning-a-resource). Other handles may offer no duplication operation; check the type's API rather than assuming that every resource has a `clone` method.

## Moving a field out

Move a field into a new owner when you no longer need that field in the original record. This avoids cloning a large value just to store it somewhere else.

Save as `batches.ms` and run `ms run batches.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"scores\n[3, 4]\n","filename":"batches.ms"} -->
```manuscript
type Report:
    title: String
    rows: List[Int]

export fn main() Int:
    let report = Report("scores", [3, 4])
    let batches = [report.rows]
    print(report.title)
    print(batches[0])
    return 0
```

```text
scores
[3, 4]
```

- The outer list owns `report.rows` after construction. The sibling field `report.title` remains readable because fields are tracked separately. Reading `report.rows` or using the whole `report` afterwards is rejected; use `report.rows.clone()` at construction if both owners need the rows.
- Field moves apply to owned fields (strings, lists, records, resources) of a `let` binding or consuming parameter; moving a resource field into a new list has a [current native-compilation limitation](#resource-field-transfers). Elements (`xs[i]`), borrowed values, `var` bindings and parameters, loop variables, closure captures, and records that declare `close` need another ownership strategy, such as cloning a clonable value or moving the whole owner.
- A parameter whose field is moved into another owner is consumed: its caller gives up the record. Passing `.clone()` keeps an independent caller-owned record.

Reading a field is different from moving it. `let rows = report.rows` borrows it. A getter that returns the field also returns an inferred borrow:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[3, 4]\n[3, 4]\n"} -->
```manuscript
type Report:
    title: String
    rows: List[Int]

fn rows_of(report: Report) List[Int]:
    return report.rows

export fn main() Int:
    let report = Report("scores", [3, 4])
    let rows = rows_of(report)
    print(rows)
    print(report.rows)
    return 0
```

```text
[3, 4]
[3, 4]
```

Calling `rows_of(report)` leaves `report.rows` readable; the record must stay available while the returned borrow is used. See [borrow-returning functions](references.md#borrowing).

### Resource field transfers

Ownership transfers cleanup responsibility with a resource. Current alpha limitation: a helper that appends a resource field to a new list and returns that list passes `ms check` but fails native compilation. This occurs with a parameter or a locally constructed record as the holder. For this use case, move the whole resource holder instead. The following program transfers a `Room` and both doors into a list:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"returned 1 room\nclose 2\nclose 1\n"} -->
```manuscript
import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit!:
        print("close {self.id}")
        return ok(unit)

type Room:
    door: Door
    spare: Door

fn carry(room: Room) List[Room]:
    return [room]

export fn main() Int:
    let rooms = carry(Room(Door(1), Door(2)))
    print("returned {rooms.length()} room")
    return 0
```

```text
returned 1 room
close 2
close 1
```

The list owns the room after `carry` returns. Both doors remain open until that list leaves scope, then close in reverse field order. Moving the whole holder avoids a partial move without cloning a resource. A place and a part of it (`r.room` and `r.room.door`) cannot both be moved out of one binding.

## Domain identity

Wrap identifiers in their own records so they cannot be mixed up.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"42\n42\n"} -->
```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String

export fn main() Int:
    let customer = CustomerId("42")
    let order = OrderId("42")
    print(customer.value)
    print(order.value)
    return 0
```

```text
42
42
```

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["expected OrderId, found CustomerId"]} -->
```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String

export fn main() Int:
    let customer_id = CustomerId("42")
    // Rejected: equal field shapes do not make nominal types interchangeable.
    let order_id: OrderId = customer_id
    return 0
```

The diagnostic includes `expected OrderId, found CustomerId`.

Identity is module, declaration, and type arguments; alternate import paths to one module do not create new types. Applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a record exports its constructor and every field; there are no per-field visibility modifiers; [`export opaque type`](#opaque-types) hides all fields outside the declaring file. Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including nested types. Importing a record does not import its field types' names.

## Recursive data

Records and alternatives may refer to themselves or each other directly, with no box. Give construction an endpoint with a base case, `Optional`, or a collection.

Save this test as `example.ms` and run `ms test example.ms`:

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::recursive expression\nPASS example.ms::recursive expression\n1 tests, 0 failed\n"} -->
```manuscript
import panic from "@std/core.ms"

enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)

fn evaluate(expr: Expr) Int:
    match expr:
        Num(value): return value
        Add(left, right): return evaluate(left) + evaluate(right)

test "recursive expression":
    let expr = Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
```

```text
RUN example.ms::recursive expression
PASS example.ms::recursive expression
1 tests, 0 failed
```

A linked record ends with an absent successor; a link owns its successor, so a clone copies the whole chain:

Save this test as `example.ms` and run `ms test example.ms`:

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::recursive links\nPASS example.ms::recursive links\n1 tests, 0 failed\n"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

type Node:
    value: Int
    next: Node?

test "recursive links":
    var node = Node(value: 1, next: none)
    node.next = Node(value: 5, next: none)
    var copy = node.clone()
    copy.next = Node(value: 2, next: none)
    let original_next = try node.next.ok_or(Error("original link is missing"))
    let copied_next = try copy.next.ok_or(Error("copied link is missing"))
    try expect_equal(original_next.value, 5)
    try expect_equal(copied_next.value, 2)
```

```text
RUN example.ms::recursive links
PASS example.ms::recursive links
1 tests, 0 failed
```

Constructors still need every required field, and a binding is unavailable in its own initializer, so `let node = Node(value: 1, next: node)` is rejected. `.clone()` copies the whole chain. Recursive shapes derive no `Hashable`; keys need explicit implementations ([equality and hashing](equality-and-hashing.md)).

Generic recursion must preserve type parameters along every cycle; see [finite recursive applications](generics.md#finite-recursive-applications).

## Opaque types

`export opaque type Approved:` hides record fields outside the declaring file; `export opaque enum Choice:` hides enum cases in the same way. The module exports functions and methods that build and read the value; other files can hold it, pass it, call its methods, and clone it when its fields are clonable.

```text
# gate.ms
export opaque type Approved:
    entity: String
    nonce: String

export fn approve(entity: String) Approved: Approved(entity: entity, nonce: "n1")

# agent.ms
let a = Approved(entity: "u2", nonce: "x")   # error: Approved is opaque outside gate.ms
let n = approve("u2").nonce                  # error: field nonce is hidden
let {entity} = approve("u2")                 # error: its fields cannot be destructured here
```

Outside the declaring file an opaque type allows no construction, field read or write, field pattern, `match` on its cases, and no `impl` (so no new methods or interface implementations). Its text form, in interpolation, `to_string()`, and test output, is only the type name: `"{a}"` is `Approved`. It is never `Data`, so `json.parse`, `json.stringify`, and typed JSON stream codecs reject it at compile time. Promises and pipes do not require `Data`.

Opaque controls visibility: an opaque value can still be cloned when its fields permit it, so it proves where a value was built, not that it is spent once. Hold a resource or a non-clonable field for single use.

## Resource fields

A record owns the resources moved into its fields and closes the fields it still owns when its scope ends. Moving a field out transfers that cleanup duty to the new owner. Such a record is not clonable. See [aggregate cleanup](../cleanup/closeable.md#records-and-collections-close-what-they-hold).

Use [enums](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md).
