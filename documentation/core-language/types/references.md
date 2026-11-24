+++
title = "Mutation and references"
weight = 5
+++

# Mutation and references

## How memory works

Numbers, booleans and other primitives (`Int`, `Float`, `Bool`, `Void`, enums without payloads) copy freely, and `.clone()` on one returns the same value.

Everything else, including strings, types, lists and maps, has exactly one owner: a binding, a field, or a slot in another value. Scope exit releases values still owned there. Such a value is handed around by borrowing until you put it somewhere that must own it:

- `b := a` and `f(a)` *borrow*: `b` and `f` read `a` in place, and `a` is still yours afterwards. `var b = a` borrows exclusively, and so does passing `a` to a `var` parameter, so changes reach `a`. The call writes `f(a)` either way (`f(var a)` is a parse error): the callee's signature says which, as it does for `move`.
- Storing a value in a field or a collection, returning a new value, or binding it at its last use *moves* it. After a move the old name is dead and the new owner frees it.
- `.clone()` is the only way to copy. Write it when you want an independent value that outlives or diverges from the original. Borrowing lets a function work with existing data without a deep copy.

The compiler checks that borrows do not outlive their owners. While a borrow lives, the owner cannot change or be reassigned, and the borrow cannot escape the owner's lifetime. Clone when a new owner needs to keep the data independently.

A function can return a borrow of an argument without any marker. Wrapping a borrowed part in `Optional` or `Result`, or forwarding a borrowed error with `?`, preserves that borrow, and the caller keeps the owner available while it uses the result. See the [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md) for the compiler contract.

## Borrowing

A borrow is a handle to a value that another binding owns. Until the borrow's last use there may be many readers or one writer. Binding a place borrows it without a marker: `x := a.b` is a shared borrow and `var x = a.b` is an exclusive one. A loop variable and a match payload borrow the same way.

- A function can return a borrowed part of a parameter or receiver: `fn list() List[Int]: return self.items`. A binding of that result borrows the original place; `xs := b.list()` reads it and `var xs = b.list()` changes it exclusively.
- `Optional` and `Result` can carry borrowed payloads. When the relevant return paths borrow the payload, `ok(self.name)` or `self.slots.get(i)` keeps it borrowed; `null` needs no owner. A `Result` can own its success value while borrowing its error from an argument, and `?` preserves the ownership of the active case. Clone a borrowed payload before storing it in a new owner.
- A returned part cannot be mixed with a newly owned value on another path; clone the part when the result needs to own it. The checker considers all return paths, so wrapping a part does not make every function return a borrow. A call through a lambda or an interface owns its result ([moving into a function](#moving-into-a-function)).
- A call that borrows from a temporary must leave an owned result. It can move the whole temporary, but retaining a part requires a clonable result. To borrow a part of a non-clonable value, bind the argument first.
- A field owns its value. A type cannot hold a view of another variable.
- A place that is changed in place (a `var` argument, a `var` receiver, a `var` borrow, a closure that assigns) may not overlap any other operand or live borrow in the same call or scope.
  - Distinct fields (`var p.left`, `var p.right`) and distinct non-negative literal list indexes (`var xs[0]`, `var xs[1]`) are disjoint. Every other pair of element accesses (`xs[i]`, `xs[0]` with `xs[-1]`, map entries) may be the same element and is rejected, as is any change to the list itself while an element borrow is live.
  - A read that finishes before the change starts, such as an `Int` argument `f(xs, xs[0])` where `f` takes `var xs`, stays valid.
  - A method's receiver and a function value held in a variable are read in place while the arguments run, so no argument (a `match` arm included) may reassign that variable. `f(match m: _: f = g; 1)` and `r.m(match m: _: r = other; 1)` are rejected; reassign before the call instead.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Box:
    items: List[Int]

fn Box.list() List[Int]:
    return self.items

fn grow(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```
`grow` returns the new length: `xs` borrows `b.items` through `list`, so `append` reaches `b`. `var xs = b.list().clone()` gives `xs` its own list.

The standard library follows the same rule: `List.first`, `List.last` and `Map.get` borrow their element.

- `x := m.get(k)` keeps `m` unchangeable until `x` is last used, and `x := m.get(k).get()` borrows the entry the same way.
- `if var x = m.get(k)` and `var x = m.get(k).get()` change the entry in place. The second faults when the key is missing.
- Use `if v := x` to read a borrowed resource or function value without moving it out of its container.

## Moving into a function

The compiler infers how a function with a body treats each argument. A parameter that the body stores, returns, or hands to another owner is taken from the caller, and the caller's name is dead after the call.

A signature with no body to read (an interface operation, a function type, or a standard-library native) borrows each argument unless it says `move`:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type Item:
    name: String

interface Sink:
    fn add(move item: Item) Int

type Log:
    count: Int

fn Log.add(move item: Item) Int:
    return item.name.length()

fn send(s: Sink, move item: Item) Int:
    return s.add(item)
```

- `move name: Type` says the callee takes the argument; `fn move Type.name` takes the receiver (`move fn name` in an interface). A caller writes nothing: the argument moves at its last use, and using it afterwards is an error.
- `move` may be written on any function. Written on one with a body, it is the declared mode: a `move` parameter the body only reads is dropped when the body ends.
- A type meets an interface operation only when its method writes `move` exactly where the operation does, as with `var` parameters.
- A function type carries `move`: `fn(move Item) Int` and `fn(Item) Int` are different types, and an anonymous function takes its modes from the expected type (`fn move x: ...`).
- The standard collections declare what they keep: `fn var List[T].append(move value: T)`, `Map.add(move key: T, move value: U)`, `fn move BytesBuilder.build()`. A method value has the same modes as the call, so `xs.append` is a `fn(move T) Void` and `append(name)` takes `name` just as `xs.append(name)` does.
- A function without a body returns a new value. A call through an interface or a function value always owns its result, so a method that returns its own field (`return self.name`) cannot meet an interface operation; return `self.name.clone()`.
- `move` and `var` do not combine on one parameter.

## Reassignment

- A `:=` binding cannot be reassigned, and neither can a resource held in one.
- Reassigning an owning `var` drops its previous value and closes any resources it held. Scope-end cleanup then closes its final value. Closing early with `close()` moves the value, so scope end has nothing left to close. See [scope-end cleanup](../cleanup/scopes.md).
- A live borrow prevents reassignment.
- Every binding is initialized at declaration, and an outer `var` keeps its declared type.
- Non-escaping closures borrow their captures. Escaping closures own them, so a function moves a parameter that an escaping closure captures; the caller passes `.clone()` to keep the value.
- Borrowed roots cannot be changed or moved while the borrow is live.

See [bindings](../basics/bindings.md), [closure captures](../functions/function-values-and-closures.md), and [scope-end cleanup](../cleanup/scopes.md).

## Index assignment

`place[key] = value` is a call of the type's `set` (a Map's `add`). The checker takes the key at the store, after `value` has run, so `value` may read `key`: `counts[key] = counts.get_or(key, 0) + 1` and `sizes[k] = k.length()` are accepted.

`value` may only read `key`; it cannot move or change it (`m[k] = bump(k)` is rejected when `bump` takes `var k`). After the store, `key` cannot be used unless it is a scalar or the store used a `.clone()` of it.

## Data copies

`.clone()` is a deep copy of nested values. Opaque handles and function values have no clone and are never copied, and a value that holds one is not `Clonable` either. See [mutation and cloning](named-types.md#mutation-and-cloning).

## Sharing a value

There is no shared mutable value. A value has one owner; a promise reads what it captures, and changes travel as messages over a `pipe` to the owner. See [concurrent tasks](../concurrency/_index.md).

## References inside other values

Fields and collection slots own their values. Moving a resource into one transfers the cleanup duty to the holder. At scope end, a holder closes the resources it owns, including nested parts. Its own `Closeable.close`, if present, runs before its parts. See [the close-order table](../cleanup/closeable.md#types-and-collections-close-what-they-hold).

A borrow of a resource field keeps the holder available and prevents closing or changing it while that borrow is still used. Destructuring transfers only the fields that move out; omitted resource fields are still closed. A resource field of a mutable holder moves out only when the next statement refills it (`part := holder.field`, then `holder.field = ...`); otherwise move the whole holder.

## Memory and open resources

Owned values are dropped deterministically; there is no tracing garbage collector. Releasing a file, socket, or other external resource is separate. Use `close()`, or let the scope that owns the resource close it.

A borrow keeps its owner available until the borrow ends, but it does not extend the lifetime of the external resource. `close()` is a `move` method, so it takes the resource like any move: the name is moved afterwards. A borrow takes on no cleanup duty; an owning closure or promise does take on the duties of the resources it owns.

## Returning a resource

A factory returns an open resource by moving it to the caller. Returning a locally owned resource transfers its cleanup duty; the factory does not close the moved value on its way out. A resource left owned by a local binding closes when that scope ends. A borrow cannot escape a local owner that is about to close.

A use after `close()` is a use after move, a compile error. A handle another owner still holds, such as a clone of a file handle, returns its closed-state error after it is closed.

See [Closeable](../cleanup/closeable.md), [scope-end cleanup](../cleanup/scopes.md), and [closures](../functions/function-values-and-closures.md).
