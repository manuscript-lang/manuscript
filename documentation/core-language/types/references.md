+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

## How memory works

Every value has exactly one owner: a variable, a field, or a slot in a collection. When the owner goes out of scope, the value is freed, right there and on time. There is no garbage collector and no reference counting, and the compiler never copies a value behind your back. Numbers, booleans and other primitives (`Int`, `Float`, `Bool`, `Unit`, alternatives without payloads) are the exception: they own nothing, so they copy freely.

Everything else, including strings, records, lists and maps, is handed around by reference until you put it somewhere that must own it:

- `let b = a` and `f(a)` *borrow*: `b` and `f` read `a` in place, and `a` is still yours afterwards. `var b = a` and `f(var a)` borrow exclusively, so changes reach `a`.
- Storing a value in a field or a collection, returning a new value, or binding it at its last use *moves* it. After a move the old name is dead and the new owner frees it.
- `.clone()` is the only copy. Write it when you want a value of your own that outlives or diverges from the original.

The compiler checks that references stay in bounds. While a borrow lives, the owner cannot change or be reassigned, and the borrow cannot be stored, returned, or captured by a closure that outlives it. If you want that, clone. Nothing dangles at runtime because the checker refuses the program first.

Functions join in: when every return path hands back a part of a parameter, the result *is* that part, and the caller holds the arguments while it uses it. Wrapping the part in an `Optional` or a `Result`, passing an error on with `try`, or converting it to an interface keeps it a reference, so `return ok(r.name)` and `return cause` as `Error` cost no copy. The sections below give the exact rules; the compiler's own notes are in the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md).

## Borrowing

A borrow is a handle to a value another binding owns: many readers, or one writer, until the borrow's last use. Binding a place borrows it without a marker: `let x = a.b` is a shared borrow and `var x = a.b` an exclusive one. A loop variable and a match payload borrow the same way.

- A function that returns a part of a parameter or the receiver on every path returns a reference to it (a lending function): `fn list() List[Int]: return self.items`. The caller holds the result as a borrow of the arguments, so `let xs = b.list()` reads `b.items` in place and `var xs = b.list()` changes it. Storing or returning the result elsewhere needs `.clone()`, and a function that returns a part on one path and a new value on another is an error until the part is cloned. Wrapping the part keeps it a reference: `fn first() String?: return self.items[0]` and `fn name() String!Missing: return ok(self.name)` lend, and `try` hands a lent error on. Converting it to an interface keeps it one too: `fn first_error(cause: Cause) Error: return cause` and `return error(cause)` as `Int!` return a view of `cause`, the caller holds `cause` while the view lives, and `let e: Error = cause` binds such a view. Storing a view needs an owned value (`cause.clone()` before the conversion). An interface with a `var fn` operation, such as `ReadStream`, is the one conversion that still copies a borrowed value, since calls through it may change the value. A lambda or an interface method always owns its result. Names bound to a lending result are borrows: `let first = xs.first()` keeps `xs` readable but not changeable until `first` is last used. A lending call over a temporary argument owns its result: the temporary itself when the function hands it back whole, otherwise a copy of the part, so the result type must be `Clonable`; for a `Regex` or another value with one owner and no `clone`, bind the argument first.
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
`grow` returns the new length: `xs` borrows `b.items` through `list`, so `append` reaches `b`. `var xs = b.list().clone()` gives `xs` its own list. The standard library follows the same rule: `List.first`, `List.last` and `Map.get` lend the element, so `let x = m.get(k)` keeps `m` unchangeable until `x` is last used and `if var x = m.get(k)` changes the entry in place; `trim` and `Optional.get` return owned values. `Error.message` is an interface method, so an implementation that returns a stored field writes `.clone()`.

## Reassignment

- Reassigning a `var` replaces its value; it does not close the old object or affect other references. A `let` cannot be reassigned.
- A resource in a `let` binding cannot be reassigned. A `var` binding can change, and the scope-end cleanup closes its final value. Closing early is fine because `close()` is idempotent. See [scope-end cleanup](../cleanup/scopes.md).
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow captures; escaping closures own them, so a parameter captured by one is consumed by the function (the caller passes `.clone()` to keep the value). Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles have no built-in clone and are never copied. See [mutation and cloning](records.md#mutation-and-cloning).

## Sharing a value

There is no shared mutable value. A value has one owner; a promise reads what it captures, and changes travel as messages over a `pipe` to the owner. See [concurrent tasks](../concurrency/_index.md).

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
