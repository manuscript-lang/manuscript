+++
title = "Go representation: reference or value"
weight = 20
+++

# Go representation: reference or value

Each Manuscript type lowers to exactly one Go type, chosen by `goType` in `pkg/lower/types.go`. The choice is a language rule: Manuscript aliases mutable data, so copying a Go value where the language promises sharing is a silent bug.

## The rule

A type is a **reference** (Go pointer, or a type holding one) when a holder can observe another holder's mutation or identity. Every other type is a **value** and is never mutated after construction.

| Manuscript type | Go type | Class | Why |
| --- | --- | --- | --- |
| `Int`, `Float`, `Bool`, `String` | `int`, `float64`, `bool`, `string` | value | Immutable. |
| `Unit` | `rt.Unit` | value | One value. |
| record | `*Name` | reference | Fields mutate; aliases observe; `.clone()` copies. |
| `List`, `Map`, `Set`, `Bytes` | `*rt.List[T]`, `*rt.Map[K,V]`, `*rt.Set[T]`, `*rt.Bytes` | reference | Mutable storage shared by aliases. |
| native handle (file, socket, task, guard, ...) | `*rt.Handle` | reference | Identity; closing affects all aliases. |
| function value | `func(*rt.Execution, ...) R` | value | Closures snapshot captured locals; captured reference values stay shared. |
| alternative (sum type) | sealed interface of `Name_Case` structs | value | Cases are immutable; their payloads keep their own class. |
| `Optional[T]` | `rt.Option[T]` | value | Immutable wrapper; `T` keeps its class. |
| `Result[T, E]` | `rt.Result[T, E]` | value | Immutable wrapper; payloads keep their class. |
| contract | Go interface over generated view structs | value | A view holds its receiver; the receiver keeps its class. |

A value type holding a reference shares it: `Optional[List[Int]]` copies the wrapper, not the list.

## Consequences the lowerer must honor

- Never address or mutate a value struct; only records, collections, and handles are written through pointers.
- Assignment, argument passing, capture, and `return` copy the Go value as is. Add no copies for references.
- `.clone()` is the only operation that copies a reference type, and it is shallow.
- Construction always allocates; `nil` never represents `none`, so use `rt.Option`.
- Representation does not decide equality: records and collections use structural equality unless `Equal` and `Hashable` implementations override it. See [equality and hashing](../core-language/types/equality-and-hashing.md).

## Adding a type

Classify it in the table first, then add `goType` and a `TestRepresentation` row in `pkg/lower`. A type fitting neither class needs a language decision.

## Parameters, defaults, and equality

- A parameter with a default is `rt.Arg[T]{Val, Set}`, filled in by the callee. Native functions, record constructors, and standard contracts take plain parameters and callers evaluate defaults.
- A `Map` or `Set` carries an `*rt.Keys[K]` fixed at construction: `nil` is Go equality, structural keys project to a comparable array, and explicit `Equal`/`Hashable` becomes `rt.CustomKeys`.
- A contract value is a generated view struct holding its receiver (`self`), plus `Describe` and `Receiver`. Views are per implementation scope when any module declares a local implementation.

## Local records keep their pointer representation

Records always remain pointers. Go escape analysis can keep a local `&Name{...}`
on the stack. A per-type value representation would break calls that mutate the
caller's record.

A checked-use inventory can prove a fresh local record with one concrete Int
field has no aliases or captures. For exact two-statement methods that update
that field by an Int parameter and return it, function-local interval analysis
may expand a discarded call into the same individual field update when overflow
is impossible. Arguments execute before the update. Generic records, defaults,
other methods, unknown bounds and Debug retain ordinary checked calls. This
changes neither the record's Go type nor the general method's behavior.

## Closed local Int maps

A fresh immutable local `Map[Int, Int]` may use alternate internal storage when
an exhaustive checked-use inventory proves every use is a direct native
`add` statement (discarding its result), `get`, `contains`, or `length` call.
Aliases, captures, defaults, views, custom equality/hash evidence and any other
use retain ordinary ordered maps. Debug also retains ordinary maps.

The Go type and layout remain `*rt.Map[int, int]`. Compiler-only
`NewLocalIntMap` / `LocalIntMap_*` helpers interpret its existing `index` as
key-to-value storage, rather than key-to-ordered-slot storage. They are exclusive
consumers: an ordinary Map operation must never receive that internal storage.
All uses of a binding select this path together or none do. Order and concurrent
sharing cannot be observed under this proof; ordinary maps retain both contracts.
