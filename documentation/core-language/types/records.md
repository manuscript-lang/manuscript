+++
title = "Records and nominal types"
weight = 1
+++

# Records and nominal types

A record groups named fields into one value. Fields can change through a `var` receiver; plain records copy implicitly and other records follow move and borrow rules (`.clone()` makes an explicit deep copy), and each declaration is a distinct nominal type.

```manuscript
type Customer:
    name: String
    email: String?
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

A default may use earlier fields and module declarations, but not itself or later fields. It is evaluated on each construction, so collection defaults are fresh. Any supplied value, even `()`, `none`, or zero, skips the default. Generic arguments never come from defaults.

## Mutation and cloning

Methods come from `impl Type:` or `impl Interface for Type:` ([explicit implementations](contracts.md#explicit-implementations)); methods inside the record are rejected. A method can update receiver fields in place:

```manuscript
interface Counter:
    var fn increment() Unit

type Val:
    val: Int

impl Counter for Val:
    var fn increment() Unit:
        self.val = self.val + 1
```

Field writes keep the declared type; the receiver evaluates once, before the new value. Plain records copy; other records follow move and borrow rules. Closures borrow or own their captures. A function changes its caller's value through a `var` parameter.

`.clone()` is a deep copy of nested records and collections; changing a clone never affects the original. Resource handles are never copied.

Records, alternatives, `List`, `Map`, `Set`, and `Bytes` have `.clone()`. Files, sockets, queues, synchronization objects, guards, and other service handles do not; a cloned record keeps the same handle.

## Moving a field out

A field of an owned record or parameter moves out at the field's last use, so extracting a large field needs no `.clone()`:

```manuscript
type Report:
    title: String
    rows: List[Int]

fn rows_of(r: Report) List[Int]:
    return r.rows

fn count_both(r: Report) Int:
    let n = rows_of_copy(r.rows)
    return n + r.title.length()

fn rows_of_copy(rows: List[Int]) Int:
    return rows.length()
```

- Each function above consumes the record; `r.title` stays usable after `r.rows` moved because fields are tracked separately. Using `r.rows` again, or the whole `r`, after the move is `is moved here but used again`; `r.rows = value` makes the field usable again.
- It applies to owned fields (strings, lists, records, resources) of a `let` binding or parameter. Elements (`xs[i]`), `ref` fields, borrowed values, `var` bindings and parameters, `for` variables, closure captures, and records that declare `close` still need `.clone()` or a whole-value move.
- `let x = r.rows` stays a borrow of the field; pass `r.rows` directly to the consuming call or `return` instead.
- A parameter with a field moved out is consumed: the caller gives the record up (`.clone()` at the call keeps it).

A resource field moves without a copy, and the new owner closes it. The record closes only the fields that were not moved, last declared first, on every way out of the function:

```manuscript
import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

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

Exporting a record exports its constructor and every field; there are no per-field visibility modifiers; [`export opaque type`](#opaque-types) hides all fields outside the declaring file. Field types must satisfy [public signature closure](../modules/declarations.md#public-signature-closure), including nested types. Importing a record does not import its field types' names.

## Recursive data

Records and alternatives may refer to themselves or each other directly, with no box. Give construction an endpoint with a base case, `Optional`, or a collection.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/core.ms"

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)

fn evaluate(expr: Expr) Int:
    match expr:
        Num(value): return value
        Add(left, right): return evaluate(left) + evaluate(right)

test "recursive expression":
    let expr = Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
```

A linked record ends with an absent successor; a link owns its successor, so a clone copies the whole chain:

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

Constructors still need every required field, and a binding is unavailable in its own initializer, so `let node = Node(value: 1, next: node)` is rejected. `.clone()` copies the whole chain. Recursive shapes derive no `Hashable`; keys need explicit implementations ([equality and hashing](equality-and-hashing.md)).

Generic recursion must preserve type parameters along every cycle; see [finite recursive applications](generics.md#finite-recursive-applications).

## Opaque types

`export opaque type Approved:` hides the fields of a record, or the cases of an alternative, outside the file that declares it. The module exports functions and methods that build and read the value; every other file can hold, pass, copy, and clone it, and call its methods.

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

Outside the declaring file an opaque type allows no construction, field read or write, field pattern, `match` on its cases, and no `impl` (so no new methods or interface implementations). Its text form, in interpolation, `to_string()`, and test output, is only the type name: `"{a}"` is `Approved`. It is never `Data`, so `json.parse`, `json.stringify`, and the message types of processes, workers, tasks, and channels reject it at compile time.

Opaque is visibility, not ownership: an opaque value can still be copied and cloned, so it proves where a value was built, not that it is spent once. Hold a resource or a non-clonable field for single use.

## Resource fields

A record holding a resource neither closes it nor extends its lifetime; cleanup follows [resource scopes](../cleanup/scopes.md). Copying does not duplicate native services.

Use [alternatives](alternatives.md) for a choice among cases and `interface` for [operation contracts](contracts.md).
