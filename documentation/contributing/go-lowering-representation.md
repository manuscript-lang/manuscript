+++
title = "Go representation: reference or value"
weight = 20
+++

# Go representation: reference or value

Every Manuscript type lowers to exactly one Go type, chosen by `goType` in `pkg/lower/types.go`. The choice is a language rule, not an optimization: Manuscript aliases mutable data, so a Go value copy where the language promises sharing is a silent semantic bug.

## The rule

A type is a **reference** (Go pointer, or a type holding one) when the language lets a holder observe another holder's mutation or identity. Every other type is a **value** (Go scalar, struct, or interface of structs) and is never mutated after construction.

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

A value type holding a reference type shares that reference. `Optional[List[Int]]` copies the wrapper, not the list.

## Consequences the lowerer must honor

- A value struct is never addressed or mutated. Only records, collections, and handles are written through pointers.
- Assignment, argument passing, capture, and `return` copy the Go value as is. Do not add copies for references and never share a copy of a value-class struct that something later mutates.
- `.clone()` is the only operation that copies a reference type, and it is shallow.
- A zero-valued pointer is a bug: construction always allocates. `nil` never represents `none`; use `rt.Option`.
- Equality and hashing: scalar-only records compare by value, all other reference types by identity unless an explicit `Equal` exists; see [equality and hashing](../core-language/types/equality-and-hashing.md).

## Adding a type

New runtime types classify themselves with this table first. Add the row, then `goType`, then the `TestRepresentation` row in `pkg/lower`. A type that fits neither class needs a language decision, not a lowering decision.

## Parameters, defaults, and equality

- A parameter that declares a default is an `rt.Arg[T]{Val, Set}`. The callee fills in an omitted argument in its own scope; native functions, record constructors, and standard contracts take plain parameters and the caller evaluates their defaults.
- A `Map` or `Set` carries an `*rt.Keys[K]`. `nil` means Go equality; structural keys project to a comparable array; an explicit `Equal`/`Hashable` becomes `rt.CustomKeys`. The collection keeps the keys it was built with.
- A contract value is a generated view struct holding its receiver (`self`), plus `Describe` and `Receiver`. Views are per implementation scope when any module declares a local implementation.

## Local records need no special case

Records are always pointers, and the lowerer does not track which ones are mutated. A record that never leaves its function does not allocate: Go's escape analysis keeps `&Name{...}` on the stack (measured 0 allocs, 0.38 ns for a local pointer vs 0.62 ns for a struct value). A value representation chosen per type would be wrong anyway, because argument passing retains the same instance, so a callee can mutate a record the caller built.
