# Generic operations in interfaces and impls

Issue #1331. `List.min_by`/`max_by` needed a method-level type parameter (`K: Comparable`), which no source construct could declare, so they stayed native with a Rust lowering arm.

## Problem

An interface operation did not parse type parameters, an `impl Iface for T` method did not parse them, and inherent source methods with type parameters were rejected by `desugar_inherent_impls`. Standard-library methods that need their own parameter had to be native declarations lowered in Rust.

## Rule

An interface operation, an impl method and an inherent method may declare type parameters with bounds. The impl repeats them in order with the same bounds; its signature must equal the operation's after renaming. Calls infer or take them explicitly. Dispatch is static (monomorphized), so such an interface works as a bound and on concrete receivers, but not as a value type: a method table has no slot for an operation whose types are open. Converting to it is a type error, and lowering leaves generic operations out of the table.

## Implementation

- Parser: `method_signature` takes generics for every operation and impl method.
- Checker: the operation's variables are recorded under `Type/name` (as native operations already were); the impl method's variables are appended to `Method.variables` and `Method::split_variables` separates them from the receiver-fixed ones; `implemented_methods` keeps them open; calls specialize them like native generic methods and record `type_args`, which lowering binds in `source_method_call`.
- The inherent-method rejection is removed.

## Evidence and alternatives

Evidence: `max_by`/`min_by` move to `stdlib/lists.ms` (about 40 lines) and the Rust arm (about 100 lines) is deleted; e2e `list-predicates.ms` passes unchanged. Doing nothing leaves every method needing its own type parameter in Rust. Allowing generic operations through interface values would need per-instance method tables; not needed here and deferred.
