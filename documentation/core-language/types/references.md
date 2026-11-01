+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Strings, records, lists, maps, sets, and alternatives are values. Scalars and records of scalars copy implicitly; a `String` is owned like a list, so storing a borrowed string in an owned position (a record field, `Map.add`, a returned value) needs an explicit `.clone()`, which makes the copy visible. Other values move at their last use into consuming positions; local place bindings and projections can borrow. `.clone()` explicitly duplicates nested data. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for parameter modes and borrow checking.

## Borrowing

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. A loop variable and a match payload borrow the same way.

- A result owns its value. A function that returns part of a parameter or the receiver returns `.clone()`: `fn list() List[Int]: return self.items.clone()`. The compiler elides the copy when the source is dead or the caller only reads the result, so a getter costs a copy only where the value is kept.
- A record field owns its value. A record cannot view another variable.
- A place changed in place (a `var` argument, a `var` receiver, a `var` borrow, a closure that assigns) may not overlap any other operand or live borrow of the same call or scope. Distinct fields (`var p.left`, `var p.right`) and distinct non-negative literal list indexes (`var xs[0]`, `var xs[1]`) are disjoint; every other pair of element accesses (`xs[i]`, `xs[0]` with `xs[-1]`, map entries) may be the same element and is rejected, as is any change to the list itself while an element borrow is live. A read that finishes before the change starts, such as an `Int` argument `f(var xs, xs[0])`, stays valid.

```manuscript
type Box:
    items: List[Int]

impl Box:
    fn list() List[Int]:
        return self.items.clone()

fn grow(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```
`grow` returns the old length: `xs` is a copy, so `append` does not reach `b`. The standard library follows the same rule: `trim`, `List.first`, `Map.get` and `Optional.get` return owned values, and a read-only use of one is not copied. `Error.message` owns its result, so an implementation may build the text; one that returns a stored field writes `.clone()`.

## Reassignment

- Reassigning a `var` replaces its value; it does not close the old object or affect other references. A `let` cannot be reassigned.
- A resource in a `let` binding cannot be reassigned. A `var` binding can change, and the scope-end cleanup closes its final value. Closing early is fine because `close()` is idempotent. See [scope-end cleanup](../cleanup/scopes.md).
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them. Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles have no built-in clone and are never copied. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

`Shared[T]` from `@std/concurrency/shared.ms` gives several owners one reference-counted value. `Shared(value)` moves the value in; copying the handle adds a holder, and the value is dropped, and closed when it is a resource, with the last holder. The handle is used like the value: its fields, `[i]`, methods and operators reach the value, and where the value's type is expected (`let n: Int = hits`, a `for`, a `match`, an `if let`) the handle gives a copy of the value, since another holder can change it afterwards.

A `var` handle changes the value and a `let` handle only reads it, under the usual rules: `hits += 1`, `stats.record(name)` and `f(var stats)` need a `var` handle. Assigning a value replaces the shared value (`names = ["a"]`); assigning another handle points the binding at that box (`names = other`). The methods of a type change the `Shared` values in its fields without being `var fn`, since the box, not the record, holds that state. A closure that changes a value through a captured handle may outlive its scope, and a `var` handle can be passed on with `var` from such a closure.

Every call on the value runs one at a time. A call that receives the value as a `var` argument, or a method that changes it, holds the box until it returns: another task's access waits its turn, and an access from the same task (a callback, or a second handle) faults with a message naming the cause. A cancelled or faulting call releases the box and keeps the changes it made so far. Keep changes that must not interleave with another task in one function or method. A `Shared` inside a worker or process message is rejected, since the other side would get a copy instead of the same box.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Shared from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

fn bump_twice(var counter: Counter) Unit:
    counter.bump()
    counter.bump()

test "change a shared value through a var handle":
    var shared = Shared(Counter([]))
    let view = shared
    shared.bump()
    bump_twice(var shared)
    view.values.length() | try expect_equal(3)
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
