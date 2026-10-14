+++
title = "Shared typed IR contract"
weight = 5
+++

# Shared typed IR contract

`ir.NewElaborator` (`ir.Elaborate`) owns the resolved facts used by scalar, call, List and record
performance work. `Elaborator.Node` supplies literal, Local, Unary, Binary,
resolved-call, match-value and record-access nodes. The Go backend translates
these facts into AST. `Elaborator` also owns Bool folding and the `Value`/`Operand` API; `Program`
and `Folder` are compatibility names for that same object, not separate
implementations. This reconciles the overlapping expression migration contract.
Unsupported statement, cleanup and dynamic/default bodies
remain explicit migration boundaries; they must not add another performance
eligibility analysis in `lower`.

| Fact | Shared representation | Backend obligation |
| --- | --- | --- |
| Source and resolved type | `Expression.Pos`, `Type`, `SourceType` | Preserve source sites and raw type before error widening |
| Value use and conversion | `Edge.Type`, `Expected`, `Never`, `ErrorSource`, `ScopedError`, `Optional` | Apply error widening before Optional wrapping; extract Never at the expected native type |
| Name/storage identity | `Local` (`Reference` compatibility name), `Binding`, `ScalarLocals`, `Callable` | Keep captures and existing boxed identity/forwarding/storage boundaries |
| Primitive operation | `Unary`/`Binary`, `Operation.Identity`, ordered operand edges | Capture an earlier value before a later effect; keep short-circuit operands in their region |
| Call identity | `ResolvedCall`, selected symbol/method, type arguments, receiver edge | Capture a receiver/callable before supplied arguments |
| Call evaluation and defaults | Written-order `Call.Arguments`, parameter `Slot`, `Parameters.Supplied`, `Omittable`, `Default` | Reorder captured values only; evaluate omitted defaults inside the callee |
| Captured List traversal | `Program.Ranges`, receiver/use edge, binding and reader suffix | Keep captured membership and a check on every iteration |
| List access and unwrap | Resolved collection operation, primitive suffix, separate `UnwrapAt` | Retain distinct access/unwrap sites and cancellation checkpoints |
| List construction | `List.Items`, parallel `List.Elements` expected-use edges | Use the authoritative constructor/initializer ABI and fresh mutable backing |
| Record representation | `Record`, `FieldUse`, resolved construction | Retain main's generated structs and runtime `Struct` compatibility |

`Source` retains original syntax for provenance and the temporary body boundary.
It does not authorize a consumer to infer operation or call identity from names.
Generic calls carry the checker's specialized parameter types. Dynamic callables
may have omission permission without an available default expression; the callable
owns preparation. Default permission is not function-type identity.

Unary Int minima and Float negative zero are elaborated as typed constants.
Their origin remains explicit so Debug retains its conservative table eligibility
while Release tables use the typed value.
Constant-table consumers use those nodes rather than parsing unary syntax again.
Effectful large literals use the same expected-use edges as scalar calls,
including Never and checked Optional/Error conversions. Initialization chunks
capture each element before the next; initialization setters add no checkpoint.

The runtime remains the ABI authority. Typed entries call raw bodies through
exactly one `SourceCall`/`ProfileSourceCall`; boxed/generated callbacks retain the
approved borrowed-argument proof. Every source loop iteration keeps its existing
cancellation check. Source-return recovery precedes delivery cancellation in the
same guard. Main's competing Enter/Leave protocol and 64-iteration polling are
reconciled with these guarantees while preserving typed scalars and records.

The original frozen source-map baseline, ordered per-callable directives and
exact-once printer markers remain verification controls. Emitting a native and
boxed body can duplicate a complete mapping; sorting directives cannot establish
correct order. The standalone printer retains main's fix for comments from
separate parsed trees, and the debugger supports both typed record fields and
active primitive List backing.

Full statement/cleanup IR is the next migration stage. This contract does not
claim that dynamic defaults, `try`, cleanup exits or all generic runtime dispatch
have already become body IR. Continue migrating each form through this shared
boundary, preserving the independent source/native/ABI and workload controls.
