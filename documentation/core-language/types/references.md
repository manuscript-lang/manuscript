+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Every value has one owner. Primitives (`Int`, `Float`, `Bool`, `Unit`, alternatives without payloads, and `Shared` handles) copy implicitly. Everything else, including strings and records, is a container of data with one owner: binding it borrows it, passing it borrows it, storing it moves it, and only `.clone()` copies it, which makes every copy visible. `.clone()` explicitly duplicates nested data. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for parameter modes and borrow checking.

## Borrowing

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. A loop variable and a match payload borrow the same way.

- A function that returns a part of a parameter or the receiver on every path returns a reference to it (a lending function): `fn list() List[Int]: return self.items`. The caller holds the result as a borrow of the arguments, so `let xs = b.list()` reads `b.items` in place and `var xs = b.list()` changes it. Storing or returning the result elsewhere needs `.clone()`, and a function that returns a part on one path and a new value on another is an error until the part is cloned. A lambda or an interface method always owns its result. Names bound to a lending result are borrows: `let first = xs.first()` keeps `xs` readable but not changeable until `first` is last used.
- A record field owns its value. A record cannot view another variable.
- A place changed in place (a `var` argument, a `var` receiver, a `var` borrow, a closure that assigns) may not overlap any other operand or live borrow of the same call or scope. Distinct fields (`var p.left`, `var p.right`) and distinct non-negative literal list indexes (`var xs[0]`, `var xs[1]`) are disjoint; every other pair of element accesses (`xs[i]`, `xs[0]` with `xs[-1]`, map entries) may be the same element and is rejected, as is any change to the list itself while an element borrow is live. A read that finishes before the change starts, such as an `Int` argument `f(var xs, xs[0])`, stays valid.

```manuscript
type Box:
    items: List[Int]

impl Box:
    fn list() List[Int]:
        return self.items

fn grow(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```
`grow` returns the new length: `xs` borrows `b.items` through `list`, so `append` reaches `b`. `var xs = b.list().clone()` gives `xs` its own list. The standard library follows the same rule: `List.first`, `List.last` and `Map.get` lend the element, so `let x = m.get(k)` keeps `m` unchangeable until `x` is last used and `if var x = m.get(k)` changes the entry in place; `trim` and `Optional.get` return owned values. `Error.message` is an interface method, so an implementation that returns a stored field writes `.clone()`.

## Reassignment

- Reassigning a `var` replaces its value; it does not close the old object or affect other references. A `let` cannot be reassigned.
- A resource in a `let` binding cannot be reassigned. A `var` binding can change, and the scope-end cleanup closes its final value. Closing early is fine because `close()` is idempotent. See [scope-end cleanup](../cleanup/scopes.md).
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them. Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles have no built-in clone and are never copied. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

`Shared[T]` from `@std/concurrency/shared.ms` gives several owners one reference-counted value. `share(value)` moves the value in; copying the `Shared` adds a holder, and the value is dropped with the last holder. `.get()` reads the value in place as a borrow.

To change the value, lock it with `lock(box)` from `@std/concurrency/sync.ms` into a `var` binding. The guard holds the payload as `guard.value` and puts it back when the binding goes out of scope, however it ends, including when the task is cancelled or returns early. Another `lock` waits until the guard is closed; a `get` while a guard holds the payload is a fault. Locking a box already held by the same task blocks; if no work can make progress, the runtime reports a deadlock fault. `ms check` rejects the visible case, a `lock` of the same written place (`box`, `self.lines`) while the guard of an earlier `lock` of it is still open (before its scope ends or its `close()`) in the same function; a second handle to the box, or a call that locks it, is caught only by the runtime. A `Shared` of a `Closeable` value is move-only, so the resource still has one owner. `take`, `put` and `locked` are internal to the standard library and rejected elsewhere. A `Shared` inside a worker or process message is rejected, since the other side would get a copy instead of the same box.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import share, Shared from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import expect_equal from "@std/test/test.ms"

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
