+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

Strings, records, lists, maps, sets, and alternatives are values. Scalars and records of scalars copy implicitly; a `String` is owned like a list, so storing a borrowed string in an owned position (a record field, `Map.add`, a returned value) needs an explicit `.clone()`, which makes the copy visible. Other values move at their last use into consuming positions; local place bindings and projections can borrow. `.clone()` explicitly duplicates nested data. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for parameter modes and borrow checking.

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

To change the value, `take()` it out, change the local, and `put` it back. One holder at a time can have it out. A second `take`, or a `get`, while it is out is a fault, so the single mutable borrow is checked when the program runs. Keep `take` and `put` in one function with no early exit between them, since only `put` returns the value. A `Shared` of a `Closeable` value is move-only, so the resource still has one owner.

```
import {share, Shared} from "@std/shared.ms"

type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

fn bump(shared: Shared[Counter]) Unit:
    var counter = shared.take()
    counter.bump()
    shared.put(counter)
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
