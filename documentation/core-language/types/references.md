+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

## How memory works

Strings, records and collections have one owner: a binding, a field, or a slot in another value. Scope exit releases values still owned there. Numbers, booleans and other primitives (`Int`, `Float`, `Bool`, `Unit`, alternatives without payloads) copy freely. Use an explicit `.clone()` when you need independent owned data; borrowing lets functions work with existing data without a deep copy.

Everything else, including strings, records, lists and maps, is handed around by reference until you put it somewhere that must own it:

- `let b = a` and `f(a)` *borrow*: `b` and `f` read `a` in place, and `a` is still yours afterwards. `var b = a` and `f(var a)` borrow exclusively, so changes reach `a`.
- Storing a value in a field or a collection, returning a new value, or binding it at its last use *moves* it. After a move the old name is dead and the new owner frees it.
- `.clone()` is the only copy. Write it when you want a value of your own that outlives or diverges from the original.

The compiler checks that borrows do not outlive their owners. While a borrow lives, the owner cannot change or be reassigned, and the borrow cannot escape the owner’s lifetime. Clone when a new owner needs to keep the data independently.

Functions can return a borrow of an argument without a marker. Wrapping a borrowed part in `Optional` or `Result`, or forwarding a borrowed error with `try`, preserves that borrow. The caller keeps the owner available while it uses the result. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for the compiler contract.

## Borrowing

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. A loop variable and a match payload borrow the same way.

- A function can return a borrowed part of a parameter or receiver: `fn list() List[Int]: return self.items`. A binding of that result borrows the original place; `let xs = b.list()` reads it and `var xs = b.list()` changes it exclusively.
- `Optional` and `Result` can carry borrowed payloads. When the relevant return paths borrow the payload, `ok(self.name)` or `self.slots.get(i)` keeps it borrowed; `none` needs no owner. A `Result` can own its success value while borrowing its error from an argument, and `try` preserves the ownership of the active case. A borrowed payload must be cloned before storing it in a new owner.
- A plain returned part cannot be mixed with a newly owned value on another path; clone the part when the result needs to own it. Wrapping a part does not make every function return a borrow: the checker considers all return paths. A lambda or an interface method owns its result.
- A call that borrows from a temporary must leave an owned result: it can move the whole temporary, but retaining a part requires a clonable result. Bind the argument first to borrow a part of a non-clonable value.
- A record field owns its value. A record cannot view another variable.
- A place changed in place (a `var` argument, a `var` receiver, a `var` borrow, a closure that assigns) may not overlap any other operand or live borrow of the same call or scope. Distinct fields (`var p.left`, `var p.right`) and distinct non-negative literal list indexes (`var xs[0]`, `var xs[1]`) are disjoint; every other pair of element accesses (`xs[i]`, `xs[0]` with `xs[-1]`, map entries) may be the same element and is rejected, as is any change to the list itself while an element borrow is live. A read that finishes before the change starts, such as an `Int` argument `f(var xs, xs[0])`, stays valid. The receiver of a method and a function value a variable holds are read in place while the arguments run, so an argument (a `match` arm among them) may not reassign that variable: `f(match m: _: f = g; 1)` is rejected, as is `r.m(match m: _: r = other; 1)`; reassign before the call instead.

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
`grow` returns the new length: `xs` borrows `b.items` through `list`, so `append` reaches `b`. `var xs = b.list().clone()` gives `xs` its own list. The standard library follows the same rule: `List.first`, `List.last` and `Map.get` borrow their element. `let x = m.get(k)` keeps `m` unchangeable until `x` is last used, and `if var x = m.get(k)` changes the entry in place. Use `if let` to read a borrowed resource or function value without moving it out of its container.

## Reassignment

- Reassigning an owning `var` drops its previous value and closes any resources it held. A live borrow prevents reassignment. A `let` cannot be reassigned.
- A resource in a `let` binding cannot be reassigned. A `var` binding can change; replacement closes its previous resource and scope-end cleanup closes its final value. Closing early is fine because `close()` is idempotent. See [scope-end cleanup](../cleanup/scopes.md).
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them, so a parameter captured by one is moved by the function (the caller passes `.clone()` to keep the value). Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles and function values have no clone and are never copied, and a value that holds one is not `Clonable` either. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

There is no shared mutable value. A value has one owner; a promise reads what it captures, and changes travel as messages over a `pipe` to the owner. See [concurrent tasks](../concurrency/_index.md).

## References inside other values

Record fields and collection slots own their values. Moving a resource into one transfers the cleanup duty to the holder. At scope end, a holder closes the resources it owns, including nested parts; its own `Closeable.close`, if present, runs before its parts. See [the close-order table](../cleanup/closeable.md#records-and-collections-close-what-they-hold).

A borrow of a resource field keeps the holder available and prevents closing or changing it while that borrow is still used. Destructuring transfers only the fields that move out; omitted resource fields are still closed.

## Memory and open resources

Owned values are dropped deterministically; there is no tracing garbage collector. Releasing a file, socket, or other external resource is separate. Use `close()`, or let the scope that owns the resource close it.

A borrow keeps its owner available until the borrow ends, without extending the external resource lifetime. Explicitly closing a resource leaves it closed for subsequent operations. A borrow does not acquire a second cleanup duty; an owning closure or promise does have the obligations of the resources it owns.

## Returning a resource

A factory returns an open resource by moving it to the caller. Returning a locally owned resource transfers its cleanup duty; the factory does not close the moved value on its way out. A resource left owned by a local binding closes when that scope ends. A borrow cannot escape a local owner that is about to close.

Use after an explicit close still returns the resource's closed-state error. Ownership transfer does not reopen a closed handle.

See [Closeable](../cleanup/closeable.md), [scope-end cleanup](../cleanup/scopes.md), and [closures](../functions/function-values-and-closures.md).
