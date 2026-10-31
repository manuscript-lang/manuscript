+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Strings, records, lists, maps, sets, and alternatives are values. Scalars and records of scalars copy implicitly; a `String` is owned like a list, so storing a borrowed string in an owned position (a record field, `Map.add`, a returned value) needs an explicit `.clone()`, which makes the copy visible. Other values move at their last use into consuming positions; local place bindings and projections can borrow. `.clone()` explicitly duplicates nested data. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for parameter modes and borrow checking.

## Borrowing with `ref`

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. `ref` is written before a function's result type or on a record field, never in a binding, element, type argument, function type or escaping closure.

- A function that returns part of a parameter or the receiver declares it: `fn list() ref List[Int]`, `fn first() ref Int?`. Without `ref` the function is rejected; return `.clone()` to own the value instead. Every path of a `ref` function returns such a part (or `none`): returning a new value, a `try` failure, a part converted to an interface, a `get` with a fallback (`o.get(default)` copies), or a borrow of a temporary built inside the function is rejected, because the caller would hold a borrow of something freed when the function returns. Drop `ref` to return owned values. A call site needs no marker: `let t = d.list()` holds a shared borrow of `d`, and `var ys = b.list()` writes through to `b` when `list` returns one plain field path of its only argument. Any other `var` binding of a `ref` call is rejected; `.clone()` it or bind it with `let`.
- A record field written `name: ref Type` makes the record a carrier that views the variable it was built from: `Cursor(source: d, position: 0)`. A carrier is used in place only: it cannot be moved, cloned, stored in a collection, or returned unless built from a read-only parameter, and its source is held unchanged until the carrier's last use.
- A binding of a place (`let x = a.b`, `var x = xs[i]`), a loop variable and a match payload borrow without a marker; `let ref`, `for ref` and `match ref` are rejected.
- A place changed in place (a `var` argument, a `var` receiver, a `var` borrow, a closure that assigns) may not overlap any other operand or live borrow of the same call or scope. Distinct fields (`var p.left`, `var p.right`) and distinct non-negative literal list indexes (`var xs[0]`, `var xs[1]`) are disjoint; every other pair of element accesses (`xs[i]`, `xs[0]` with `xs[-1]`, map entries) may be the same element and is rejected, as is any change to the list itself while an element borrow is live. A read that finishes before the change starts, such as an `Int` argument `f(var xs, xs[0])`, stays valid.
- A `ref` result freezes every borrowable argument of the call until its last use, not only the one it came from.
- An interface operation declares `ref` when its implementations lend: every implementation of a `ref` operation returns `ref`, and an owning operation cannot be implemented by a lender. A scalar result (`Int`, `Bool`, `Float?`) is the same lent or owned, so an implementation may compute it; a `Shared` handle still refers to storage, so it is not exempt. A call through the interface lends too: `view.label()` borrows from `view`, so keeping the result past `view`, or returning it from a function without `ref`, needs `.clone()`.

```manuscript
type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn grow(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```
The standard library lends nothing: `trim`, `List.first`, `Map.get` and `Optional.get` return owned values, and a read-only use of one is not copied. `Error.message` owns its result, so an implementation may build the text; one that returns a stored field writes `.clone()`.
The standard library declares its lending natives the same way (`List.first`, `Map.get`, `Optional.get`). `Error.message` owns its result, so an implementation may build the text; one that returns a stored field writes `.clone()`.

## Reassignment

- Reassigning a `var` replaces its value; it does not close the old object or affect other references. A `let` cannot be reassigned.
- A resource in a `let` binding cannot be reassigned. A `var` binding can change, and the scope-end cleanup closes its final value. Closing early is fine because `close()` is idempotent. See [scope-end cleanup](../cleanup/scopes.md).
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them. Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles have no built-in clone and are never copied. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

`Shared[T]` from `@std/shared.ms` gives several owners one reference-counted value. `share(value)` moves the value in; copying the `Shared` adds a holder, and the value is dropped with the last holder. `.get()` reads the value in place as a borrow.

To change the value, lock it with `lock(box)` from `@std/sync.ms` into a `var` binding. The guard holds the payload as `guard.value` and puts it back when the binding goes out of scope, however it ends, including when the task is cancelled or returns early. Another `lock` waits until the guard is closed; a `get` while a guard holds the payload is a fault. Locking a box already held by the same task blocks; if no work can make progress, the runtime reports a deadlock fault. `ms check` rejects the visible case, a `lock` of the same written place (`box`, `self.lines`) while the guard of an earlier `lock` of it is still open (before its scope ends or its `close()`) in the same function; a second handle to the box, or a call that locks it, is caught only by the runtime. A `Shared` of a `Closeable` value is move-only, so the resource still has one owner. `take`, `put` and `locked` are internal to the standard library and rejected elsewhere. A `Shared` inside a worker or process message is rejected, since the other side would get a copy instead of the same box.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import share, Shared from "@std/shared.ms"
import lock from "@std/sync.ms"
import expect_equal from "@std/test.ms"

type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

fn bump(shared: Shared[Counter]) Unit:
    var guard = lock(shared)
    guard.value.bump()

test "change a shared value through its guard":
    let shared = share(Counter([]))
    bump(shared)
    shared.get().values.length() | try expect_equal(1)
```

## References inside other values

Records, alternatives, collections, and closures may hold resource references. Storing a resource neither closes it nor keeps it open; arrange cleanup for the resource itself.

- Closing a resource affects every alias, including nested ones.
- Dropping an aggregate does not close its fields.
- A library object managing several resources can implement `Closeable` and close them itself.
- Builders follow the same rules.
- [Destructuring](destructuring.md) does not change cleanup.

## Memory and open resources

Owned values are dropped deterministically; there is no tracing garbage collector. Releasing a file, socket, or other external resource is separate. Use `close()`, or let the scope that owns the resource close it.

A borrow keeps its owner available until the borrow ends, without extending the external resource lifetime. Once one reference closes it, all others see it closed. Dropping a reference, closure, or work ID closes nothing.

## Returning a resource

A factory can return an open resource for its caller to own. A resource bound in the factory and not handed on is already closed when the caller receives it.

| What the function does | What the caller receives |
| --- | --- |
| Returns an open resource without registering local cleanup | An open resource; the caller must arrange cleanup. |
| Returns a resource a local binding still owns | A reference to the resource after its scope has closed it. |

Using a closed resource raises its runtime closed-state error. A `let` or `var` that holds a resource and is never moved on is closed when its scope ends; move it on (return it, pass it to a consuming parameter, or store it) to hand the duty to a new owner. A resource made by another resource, such as a child of a `ProcessGroup`, is closed by its owner. Use after close is still a runtime error, and ownership transfer does not replace explicit resource cleanup.

See [Closeable](../cleanup/closeable.md), [scope-end cleanup](../cleanup/scopes.md), and [closures](../functions/function-values-and-closures.md).
