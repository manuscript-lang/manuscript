+++
title = "Types and nominal types"
aliases = ["/core-language/types/records/"]
weight = 1
+++

# Types and nominal types

A type groups related data into named fields. Use it when a function should receive one meaningful value, such as a customer or an order. Each declaration creates a distinct type; fields change through a `var` binding.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Customer:
    name: String
    email: String?
```

Field types are explicit and field names are unique. An empty type is `type Marker:`. A field may have a default expression, which is checked against the field's type.

## Construction

Supply each required field exactly once, by position or label; fields with defaults may be omitted. Missing, duplicate, and unknown fields are compile errors.

Supplied expressions evaluate in written order, then omitted defaults evaluate in declaration order. Each is checked against its field type, so `null` and `[]` get their expected type.

<!-- manuscript-example: {"mode":"fragment","context":"type Customer:\n    name: String\n    email: String?","given":[]} -->
```manuscript
customer := Customer(name: "Ada", email: null)
name := customer.name
```

Positional arguments follow declaration order, and labels are optional under the [call rules](../functions/declarations-and-calls.md#argument-names): `Customer("Ada", null)` equals `Customer(name: "Ada", email: null)`. To handle an optional field such as `email`, see [optional values](optionals.md).

<!-- manuscript-example: {"mode":"error","contains":"","context":"type Customer:\n    name: String\n    email: String? = null","given":[]} -->
```manuscript
// An omitted optional field is null.
without_email := Customer(name: "Ada")
// Rejected: changing a field requires a var binding.
customer.name = "Grace"
```

Generic types declare parameters (`type Box[T]:`) and construct as `Box[Int](value: 1)`; see [generics](generics.md).

<!-- manuscript-example: {"mode":"fragment","given":[]} -->
```manuscript
type Options:
    count: Int = 3
    total: Int = count + 1

options := Options(count: 5)  // total defaults to 6
```

An optional field with no explicit default is `null` when omitted. A default may use earlier fields and module declarations, but not itself or later fields.

A default is evaluated on each construction, so a collection default is a fresh collection each time. Any supplied value, even `void`, `null`, or zero, skips the default. Generic arguments never come from defaults.

## Mutation and cloning

`.clone()` is a deep copy: the clone has its own nested types and collections, and changing it leaves the original alone.

Save as `customers.ms` and run `ms run customers.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\nGrace\n"} -->
```manuscript
type Customer:
    name: String
    email: String?

fn main() Void:
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

Methods are receiver methods, `fn Type.name(...)` ([methods](contracts.md#methods)); a method declared inside the type body is rejected. A method marked `var fn` can update receiver fields in place:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
interface Counter:
    var fn increment() Void

type Val:
    val: Int

fn var Val.increment() Void:
    self.val = self.val + 1
```

A field write keeps the field's declared type, and the receiver evaluates once, before the new value. A type follows the same move and borrow rules as any other owner, and only primitives copy implicitly. Closures borrow or own their captures. A function changes its caller's value through a `var` parameter.

Types, enums, `List`, `Map`, `Set`, and `Bytes` have `.clone()`. Files, sockets, queues, synchronization objects, guards, and other service handles do not, and neither does a function value, which owns its captures and has one owner.

A type, enum, or collection that holds a resource or a function value is not `Clonable`. It has no `.clone()`, and the copying collection operations (`concat`, `take`, `sorted`) do not apply to it. Move it or build it again instead.

## Moving a field out

Move a field into a new owner when the original no longer needs it. This avoids cloning a large value just to store it elsewhere.

Save as `batches.ms` and run `ms run batches.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"scores\n[3, 4]\n"} -->
```manuscript
type Report:
    title: String
    rows: List[Int]

fn main() Void:
    report := Report("scores", [3, 4])
    batches := [report.rows]
    print(report.title)
    print(batches[0])
```

```text
scores
[3, 4]
```

- The outer list owns `report.rows` after construction. The sibling field `report.title` stays readable because fields are tracked separately. Reading `report.rows` or using the whole `report` afterwards is rejected. If both owners need the rows, use `report.rows.clone()` at construction.
- Field moves apply to owned fields (strings, lists, types, resources) of a `:=` binding or a consuming parameter. They do not apply to elements (`xs[i]`), borrowed values, `var` bindings and parameters, loop variables, closure captures, or types that declare `close`. For those, clone a clonable value or move the whole owner.
- A parameter whose field is moved into another owner is consumed, so the caller gives up the whole value. Pass `.clone()` to keep an independent caller-owned value.

Reading a field is different from moving it: `rows := report.rows` borrows the field. A function that returns the field also returns an inferred borrow:

<!-- manuscript-example: {"mode":"fragment","context":"type Report:\n    rows: List[Int]","given":[]} -->
```manuscript
fn rows_of(report: Report) List[Int]:
    return report.rows
```

Calling `rows_of(report)` leaves `report.rows` readable, and `report` must stay available while the returned borrow is in use. See [borrow-returning functions](references.md#borrowing).

A resource field moves without a copy, and the new owner closes it. The type closes only the fields that were not moved, last declared first, on every way out of the function. In this example `door` is moved and `spare` is not:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Closeable from "@std/core.ms"

type Door:
    id: Int

fn move Door.close() Void!:
    return ok()

type Room:
    door: Door
    spare: Door

fn open_door(r: Room) List[Door]:
    var doors: List[Door] = []
    doors.append(r.door)
    return doors
```

Here `r.spare` closes when `open_door` returns, and `r.door` closes with its new owner, `doors`. A place and a part of it (such as `r.door` and `r.door.id`) cannot both be moved out of one binding.

## Domain identity

Wrap identifiers in their own types so they cannot be mixed up.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type CustomerId:
    value: String

type OrderId:
    value: String
```

<!-- manuscript-example: {"mode":"error","contains":"","context":"type CustomerId:\n    value: String\n\ntype OrderId:\n    value: String","given":[]} -->
```manuscript
customer_id := CustomerId("42")
// Rejected: equal field shapes do not make nominal types interchangeable.
order_id: OrderId := customer_id
```

A type's identity is its module, its declaration, and its type arguments. Importing one module by different paths does not create different types. Type applications are [invariant](compatibility.md).

## Public data surfaces

Exporting a type exports its constructor and every field. There are no per-field visibility modifiers; [`export opaque type`](#opaque-types) hides all fields outside the declaring file instead.

Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including nested types. Importing a type does not import the names of its field types.

## Recursive data

Types and enums may refer to themselves or each other directly, with no box. Give construction an endpoint with a base case, an `Optional`, or a collection.

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
    var node = Node(value: 1, next: null)
    node.next = Node(value: 5, next: null)
    var copy = node.clone()
    copy.next = Node(value: 2, next: null)
    if node.next.get().value != 5 or copy.next.get().value != 2:
        panic("clones must be independent")
```

Constructors still need every required field, and a binding is unavailable in its own initializer, so `node := Node(value: 1, next: node)` is rejected. Recursive shapes get no automatic `Hashable`; a key needs an explicit implementation ([equality and hashing](equality-and-hashing.md)).

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

Outside the declaring file, an opaque type allows none of the following: construction, field reads or writes, field patterns, `match` on its cases, or new methods declared in another module.

Its text form, in interpolation, `to_string()`, and test output, is only the type name: `f"{a}"` is `Approved`. It is never `Data`, so `json.parse`, `json.stringify`, and typed JSON stream codecs reject it at compile time. Promises and pipes do not require `Data`.

Opaque controls visibility only. An opaque value can still be cloned when its fields permit it, so it shows where a value was built, not that it is used once. For single use, hold a resource or a non-clonable field.

## Resource fields

A type owns the resources moved into its fields and closes the fields it still owns when its scope ends. Moving a field out transfers that cleanup duty to the new owner. Such a type is not clonable. See [aggregate cleanup](../cleanup/closeable.md#types-and-collections-close-what-they-hold).

Use [enums](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md).

## Aliases

`type Name = Type` gives another name to a type expression. An alias is not a new type: it and its target are interchangeable everywhere, and it has no constructor or methods of its own. Declare a `type` with fields when you need a distinct type.

<!-- manuscript-example: {"mode":"fragment","given":[]} -->
```manuscript
type Rows = List[Int]
type Handler = fn(Int) Int
type Maybe[T] = T?

fn total(rows: Rows) Int:
    return rows.fold(0, fn sum, x: sum + x)

numbers: List[Int] := [1, 2, 3]
sum := total(numbers)
```

- The target is any type expression, including function types, `T?`, `T!E` and applications such as `List[Row]`.
- An alias may take type parameters, written like a generic type's: `type Pairs[A: Hashable, B] = List[Map[A, B]]`. Every parameter is supplied, or defaulted, where the alias is used. Bounds apply to the expansion.
- An alias may name a type declared later in the module. A cycle (`type A = B` with `type B = A`) is rejected.
- An exported alias must not expose a private type, as with any exported signature.

## Growing a tree

A tree grows through a `fn var` method that calls itself on the child with `?.`, which does nothing while the child is absent. An `if var` on an `Optional` parameter or a move out of a field is rejected, so a mutating walk is written as a method. A function that only reads walks with `if n := node:`. A `T?` parameter has no default: write `= null` to make it omittable.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/core.ms"

type Branch:
    key: Int
    left: Branch?
    right: Branch?

fn var Branch.insert(key: Int) Void:
    if key < self.key:
        if self.left == null:
            self.left = Branch(key, null, null)
        else:
            self.left?.insert(key)
    else:
        if self.right == null:
            self.right = Branch(key, null, null)
        else:
            self.right?.insert(key)

fn count(node: Branch?) Int:
    if n := node:
        return 1 + count(n.left) + count(n.right)
    return 0

test "a tree inserts through its children":
    var root = Branch(50, null, null)
    for key in [30, 70, 20, 40]:
        root.insert(key)
    if count(root) != 5:
        panic("every key must be inserted")
```
