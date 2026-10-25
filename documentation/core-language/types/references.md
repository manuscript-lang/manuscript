+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Strings, records, lists, maps, sets, and alternatives are values. Scalars and records of scalars copy implicitly; a `String` is owned like a list, so storing a borrowed string in an owned position (a record field, `Map.add`, a returned value) needs an explicit `.clone()`, which makes the copy visible. Other values move at their last use into consuming positions; local place bindings and projections can borrow. `.clone()` explicitly duplicates nested data. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for parameter modes and borrow checking.

## Borrowing with `ref`

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. `ref` is written in one place, before a function's result type, never in a binding, field, element, type argument, function type or escaping closure.

- A function that returns part of a parameter or the receiver declares it: `def list() -> ref List[Int]`, `def trim() -> ref String`. Without `ref` the function is rejected; return `.clone()` to own the value instead. Every path of a `ref` function returns such a part (or `none`): returning a new value, a `try` failure, or a borrow of a temporary built inside the function is rejected, because the caller would hold a borrow of something freed when the function returns. Drop `ref` to return owned values. A call site needs no marker: `let t = s.trim()` holds a shared borrow of `s`, and `var ys = b.list()` writes through to `b` when `list` returns one plain field path of its only argument. Any other `var` binding of a `ref` call is rejected; `.clone()` it or bind it with `let`.
- A binding of a place (`let x = a.b`, `var x = xs[i]`), a loop variable and a match payload borrow without a marker; `let ref`, `for ref` and `match ref` are rejected.
- A `ref` result freezes every borrowable argument of the call until its last use, not only the one it came from.
- An interface operation declares `ref` when its implementations lend: every implementation of a `ref` operation returns `ref`, and an owning operation cannot be implemented by a lender. A `Copy` result (`Int`, a record of scalars) is the same lent or owned, so an implementation may compute it. A call through the interface lends too: `view.label()` borrows from `view`, so keeping the result past `view`, or returning it from a function without `ref`, needs `.clone()`.

```manuscript
type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def grow(var b: Box) -> Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```

The standard library declares its lending natives the same way (`trim`, `List.first`, `Map.get`, `Optional.get`). `Error.message` owns its result, so an implementation may build the text; one that returns a stored field writes `.clone()`.

## Reassignment

- Reassigning a `var` replaces its value; it does not close the old object or affect other references. A `let` cannot be reassigned.
- A `with` binding is immutable and registers the initialized object itself; reassigning another variable cannot change which `close()` runs. Closing early is fine because `close()` is idempotent.
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them. Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [using with](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles have no built-in clone and are never copied. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

`Shared[T]` from `@std/shared.ms` gives several owners one reference-counted value. `share(value)` moves the value in; copying the `Shared` adds a holder, and the value is dropped with the last holder. `.get()` reads the value in place as a borrow.

To change the value, lock it with `lock(box)` from `@std/sync.ms` in a `with var` block. The guard holds the payload as `guard.value` and puts it back when the block ends, however it ends, including when the task is cancelled or returns early. Another `lock` waits until the guard is closed; a `get` while a guard holds the payload is a fault. A task that locks a box it already holds waits forever. A `Shared` of a `Closeable` value is move-only, so the resource still has one owner. `take`, `put` and `locked` are internal to the standard library and rejected elsewhere. A `Shared` inside a worker or process message is rejected, since the other side would get a copy instead of the same box.

```
import {share, Shared} from "@std/shared.ms"
import {lock} from "@std/sync.ms"

type Counter:
    values: List[Int]

impl Counter:
    var def bump() -> Unit:
        self.values.append(1)

def bump(shared: Shared[Counter]) -> Unit:
    with var guard = lock(shared):
        guard.value.bump()
```

## References inside other values

Records, alternatives, collections, and closures may hold resource references. Storing a resource neither closes it nor keeps it open; arrange cleanup for the resource itself.

- Closing a resource affects every alias, including nested ones.
- Dropping an aggregate does not close its fields.
- A library object managing several resources can implement `Closeable` and close them itself.
- Builders follow the same rules.
- [Destructuring](destructuring.md) does not change cleanup.

## Memory and open resources

Owned values are dropped deterministically; there is no tracing garbage collector. Releasing a file, socket, or other external resource is separate. Use `close()` or a `with` block.

A borrow keeps its owner available until the borrow ends, without extending the external resource lifetime. Once one reference closes it, all others see it closed. Dropping a reference, closure, or work ID closes nothing.

## Returning a resource

A factory can return an open resource for its caller's `with`. A resource returned from inside a local `with` block is already closed when the caller receives it.

| What the function does | What the caller receives |
| --- | --- |
| Returns an open resource without registering local cleanup | An open resource; the caller must arrange cleanup. |
| Returns a resource registered in a local `with` block | A reference to the resource after that block has closed it. |

Using a closed resource raises its runtime closed-state error. The compiler does not catch every missing `with`, and ownership transfer does not replace explicit resource cleanup.

See [Closeable](../cleanup/closeable.md), [using with](../cleanup/scopes.md), and [closures](../functions/function-values-and-closures.md).
