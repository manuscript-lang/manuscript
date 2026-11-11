+++
title = "Types and nominal types"
aliases = ["/core-language/types/records/"]
weight = 1
+++

# Types and nominal types

A type groups related data into named fields. Use it when a function should receive one meaningful value, such as a customer or an order. Each declaration creates a distinct type; fields change through a `var` binding.

```manuscript
type Customer:
    name: String
    email: String?
```

Field types are explicit and names unique. An empty type is `type Marker:`. A field may have a default expression checked against its type.

## Construction

Supply each required field exactly once, by position or label; fields with defaults may be omitted. Missing, duplicate, and unknown fields are compile errors. Supplied expressions evaluate in written order, then omitted defaults in declaration order. Each is checked against its field type, so `none` and `[]` get their expected type.

```manuscript
customer := Customer(name: "Ada", email: none)
name := customer.name
```

Positional arguments follow declaration order and labels are optional under the [call rules](../functions/declarations-and-calls.md#argument-names): `Box(3)` equals `Box(value: 3)`. Handle an optional field as described in [optional values](optionals.md).

```manuscript
// An omitted optional field is none.
without_email := Customer(name: "Ada")
// Rejected: changing a field requires a var binding.
customer.name = "Grace"
```

Generic types declare parameters (`type Box[T]:`) and construct as `Box[Int](value: 1)`; see [generics](generics.md).

```manuscript
type Options:
    count: Int = 3
    total: Int = count + 1

options := Options(count: 5)  // total defaults to 6
```

An optional field with no explicit default is `none` when omitted. A default may use earlier fields and module declarations, but not itself or later fields. It is evaluated on each construction, so collection defaults are fresh. Any supplied value, even `unit`, `none`, or zero, skips the default. Generic arguments never come from defaults.

## Mutation and cloning

A clone gives a value its own nested data. Changing the clone leaves the original alone.

Save as `customers.ms` and run `ms run customers.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\nGrace\n"} -->
```manuscript
type Customer:
    name: String
    email: String?

fn main() Unit:
    original := Customer("Ada")
    var updated = original.clone()
    updated.name = "Grace"
    print(original.name)
    print(updated.name)
```

```text
Ada
Grace
```

Methods are receiver methods, `fn Type.name(...)` ([methods](contracts.md#methods)); methods inside the type are rejected. A method marked `var fn` can update receiver fields in place:

```manuscript
interface Counter:
    var fn increment() Unit

type Val:
    val: Int

fn var Val.increment() Unit:
    self.val = self.val + 1
```

Field writes keep the declared type; the receiver evaluates once, before the new value. Types follow the move and borrow rules of every container; only primitives copy implicitly. Closures borrow or own their captures. A function changes its caller's value through a `var` parameter.

`.clone()` is a deep copy of nested types and collections; changing a clone never affects the original. Resource handles are never copied.

Types, alternatives, `List`, `Map`, `Set`, and `Bytes` have `.clone()`. Files, sockets, queues, synchronization objects, guards, and other service handles do not, and neither does a function value: it owns its captures and has one owner. A type, alternative or collection that holds a resource or a function value is not `Clonable`, so it has no `.clone()` and the copying collection operations (`concat`, `take`, `sorted`) do not apply to it; move it, or build it again (a `Router` is moved into `mount` and into its `handler`).

## Moving a field out

Move a field into a new owner when you no longer need that field in the original type. This avoids cloning a large value just to store it somewhere else.

Save as `batches.ms` and run `ms run batches.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"scores\n[3, 4]\n"} -->
```manuscript
type Report:
    title: String
    rows: List[Int]

fn main() Unit:
    report := Report("scores", [3, 4])
    batches := [report.rows]
    print(report.title)
    print(batches[0])
```

```text
scores
[3, 4]
```

- The outer list owns `report.rows` after construction. The sibling field `report.title` remains readable because fields are tracked separately. Reading `report.rows` or using the whole `report` afterwards is rejected; use `report.rows.clone()` at construction if both owners need the rows.
- Field moves apply to owned fields (strings, lists, types, resources) of a `:=` binding or consuming parameter. Elements (`xs[i]`), borrowed values, `var` bindings and parameters, loop variables, closure captures, and types that declare `close` need another ownership strategy, such as cloning a clonable value or moving the whole owner.
- A parameter whose field is moved into another owner is consumed: its caller gives up the type. Passing `.clone()` keeps an independent caller-owned type.

Reading a field is different from moving it. `rows := report.rows` borrows it. A getter that returns the field also returns an inferred borrow:

```manuscript
fn rows_of(report: Report) List[Int]:
    return report.rows
```

Calling `rows_of(report)` leaves `report.rows` readable; the type must stay available while the returned borrow is used. See [borrow-returning functions](references.md#borrowing).

A resource field moves without a copy, and the new owner closes it. The type closes only the fields that were not moved, last declared first, on every way out of the function:

```manuscript
import Closeable from "@std/core.ms"

type Door:
    id: Int

fn var Door.close() Unit!:
    return ok(unit)

type Room:
    door: Door
    spare: Door

fn open_door(r: Room) List[Door]:
    var doors: List[Door] = []
    doors.append(r.door)
    return doors
```

Here `r.spare` closes when `open_door` returns and `r.door` closes with `doors`' new owner. A place and a part of it (`r.room` and `r.room.door`) cannot both be moved out of one binding.

## Domain identity

Wrap identifiers in their own types so they cannot be mixed up.

```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String
```

```manuscript
customer_id := CustomerId("42")
// Rejected: equal field shapes do not make nominal types interchangeable.
order_id: OrderId := customer_id
```

Identity is module, declaration, and type arguments; alternate import paths to one module do not create new types. Applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a type exports its constructor and every field; there are no per-field visibility modifiers; [`export opaque type`](#opaque-types) hides all fields outside the declaring file. Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including nested types. Importing a type does not import its field types' names.

## Recursive data

Types and alternatives may refer to themselves or each other directly, with no box. Give construction an endpoint with a base case, `Optional`, or a collection.

<!-- manuscript-example: {"mode":"test"} -->
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
    expr := Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
```

A linked type ends with an absent successor; a link owns its successor, so a clone copies the whole chain:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/core.ms"

type Node:
    value: Int
    next: Node?

test "recursive links":
    var node = Node(value: 1, next: none)
    node.next = Node(value: 5, next: none)
    var copy = node.clone()
    copy.next = Node(value: 2, next: none)
    if node.next.get().value != 5 or copy.next.get().value != 2:
        panic("clones must be independent")
```

Constructors still need every required field, and a binding is unavailable in its own initializer, so `node := Node(value: 1, next: node)` is rejected. `.clone()` copies the whole chain. Recursive shapes derive no `Hashable`; keys need explicit implementations ([equality and hashing](equality-and-hashing.md)).

Generic recursion must preserve type parameters along every cycle; see [finite recursive applications](generics.md#finite-recursive-applications).

## Opaque types

`export opaque type Approved:` hides fields outside the declaring file; `export opaque enum Choice:` hides enum cases in the same way. The module exports functions and methods that build and read the value; other files can hold it, pass it, call its methods, and clone it when its fields are clonable.

```text
# gate.ms
export opaque type Approved:
    entity: String
    nonce: String

export fn approve(entity: String) Approved: Approved(entity: entity, nonce: "n1")

# agent.ms
a := Approved(entity: "u2", nonce: "x")   # error: Approved is opaque outside gate.ms
n := approve("u2").nonce                  # error: field nonce is hidden
{entity} := approve("u2")                 # error: its fields cannot be destructured here
```

Outside the declaring file an opaque type allows no construction, field read or write, field pattern, `match` on its cases, and no new methods in another module. Its text form, in interpolation, `to_string()`, and test output, is only the type name: `"{a}"` is `Approved`. It is never `Data`, so `json.parse`, `json.stringify`, and typed JSON stream codecs reject it at compile time. Promises and pipes do not require `Data`.

Opaque controls visibility: an opaque value can still be cloned when its fields permit it, so it proves where a value was built, not that it is spent once. Hold a resource or a non-clonable field for single use.

## Resource fields

A type owns the resources moved into its fields and closes the fields it still owns when its scope ends. Moving a field out transfers that cleanup duty to the new owner. Such a type is not clonable. See [aggregate cleanup](../cleanup/closeable.md#types-and-collections-close-what-they-hold).

Use [enums](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md).
