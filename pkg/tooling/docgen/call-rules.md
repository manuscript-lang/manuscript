+++
title = "Special call rules"
weight = 3
+++

# Special call rules

The generated reference captures declaration types, bounds, fields, cases, and operations. A few APIs use checker rules beyond an ordinary function signature. These rules are implemented in `pkg/checker/calls.go`; this page must be reviewed when those rules change.

Ordinary functions and methods with exactly one declared parameter permit omitting its argument label. Functions with multiple parameters accept bare identifiers matching their parameter names as shorthand for `name: name`; other supplied expressions require labels, including when optional API parameters are omitted. Single-payload record/case constructors and contract views may also omit their label; multi-payload constructors retain explicit labels. Context supplies omitted callback parameter types, and callback bodies may infer generic result types. Single-line callable expression bodies implicitly return their value; multiline bodies keep explicit returns. Function-type labels remain part of type identity. Source functions and native declarations may declare default argument expressions; their evaluation and function-value boundaries are specified in [default arguments](https://manuscript-lang.github.io/manuscript/core-language/functions/declarations-and-calls/#default-arguments).

- `Scheduler(limit: Optional[Int], reporter: Optional[fn(failure: SchedulerFailure) -> Unit], drain: Optional[Duration], history_limit: Optional[Int])` has only optional constructor arguments. Omitted admission and history limits are unbounded. Reporters and start operations are ordinary callbacks; start may be stored as a bound method.
- `Queue[T]()` creates an unbounded local FIFO. `Queue[T](capacity: 4)` supplies a fixed positive bound through its `capacity: Optional[Int]` constructor argument; supplied payloads are wrapped once under the [optional argument rules](https://manuscript-lang.github.io/manuscript/core-language/types/optionals/#passing-optional-arguments). A nonpositive explicit capacity is a programming fault. Shared access requires `Synchronized[Queue[T]]`.
- `Synchronized[T](value: T)` stores a value behind a mutex. Its `lock()` returns a `SynchronizedGuard[T]` for `with`; guard get/set require an active acquisition, and close releases it.
- `Bytes(values: List[Int])` constructs bytes. The runtime checks the byte range.
- `List[T]()` constructs an empty list, with explicit type arguments or a complete expected List type. List literals remain available.
- `Task`, `SynchronizedGuard`, `Instant`, `Duration`, `Decimal`, and `OperationId` have no source constructor. Durations use literals; other values come from APIs or conversions.
- `.clone()` is built in on records, alternatives, List, Map, Set, and Bytes and returns the same concrete data type with separate outer storage. It does not clone nested handles or introduce a method on native services.
- Records use their listed fields as constructor arguments, with an optional label when exactly one field is declared. Alternatives construct one listed case. Interfaces describe operations implemented by explicit `impl` declarations; they are capability views rather than concrete resource constructors.
- TaskGroup.start[T] infers T from its callback and returns Task[T]. Saving start as a value requires explicit specialization; Task.join and TaskGroup.join use their source declarations.
- Native collection methods `map[U]`, `flat_map[U]`, `group_by[K: Hashable]`, `fold[A]`, and `fold_right[A]` infer method type arguments from supplied callbacks/values. Saving a generic method as a value requires explicit specialization, such as `values.map[String]`. Application-defined interface operations remain nongeneric.
- List equality searches require `Equal`; `to_set` requires `Hashable`; `join` is available only on `List[String]`. These method-specific receiver requirements are explicit in the native bindings; signatures come directly from the receiver declarations.
- Generic bounds constrain type arguments. There is no sharing bound or separate callable proof.

For lifetime, cancellation, defaults, and host behavior, read the standard library guides. A type signature alone does not establish these guarantees.
