+++
title = "Primitive List storage and Go ABI"
+++

# Primitive List storage and Go ABI

`*msruntime.List` remains the authoritative mutable identity. It owns one backing
kind: `[]int64`, `[]float64`, `[]bool`, `[]string`, or the boxed `[]Value` fallback.
Default numeric semantics remain 64-bit. Generic forwarding and bound operations
retain the same pointer; growth updates its header. A captured traversal retains
the original array and length, including valid retained tails after shrinking.

Use `NewIntList`, `NewFloatList`, `NewBoolList`, or `NewStringList` with the exact
checked type key and an ordinary typed slice. Each copies into fresh backing with
two allocations for a nonempty list. `NewList(typeKey, []Value)` checks the type
and payload before choosing a primitive kind; other payloads remain boxed.

Go consumers must use `Len`, `Cap`, `Get`, `Append`, `Set`, and `CopySlice` instead
of `Items`. `Items` remains available solely for legacy boxed construction,
including previously emitted composite literals; it is nil on typed Lists.
Writing that field on a typed List does not mutate its primitive backing. There
is no lazy boxed mirror. `Boxed()` creates an explicit independent boundary copy
and must not implement a traversal or writer.

`CaptureList(Value)` returns a `ListRange` header without allocating or copying
values. Its `Len` and `Int`, `Float`, `Bool`, `String`, or `Get` readers observe
captured backing. `Iterate(Value)` remains rangeable for older emitted programs,
now as `iter.Seq2[int, Value]`; Go callers that indexed its former slice return
must use captured readers instead. Map and Set snapshot behavior is unchanged.

`NewSizedList` and the four `NewSized*List` constructors reserve exact fresh
backing for effectful literals. `InitListValue` and the four primitive `InitList*`
setters perform non-cancelling construction writes only before
`FinishListInitialization`. Lowering owns cancellation, checked conversions,
left-to-right evaluation and source positions, and finishes before publishing.
Using an initializer after completion or outside its sized bounds faults.

`ListAtInt/Float/Bool/String` return typed Optional values with `Value` and
`Present` fields. Their `Unwrap(ctx)` methods retain the ordinary none fault and
entry/delivery cancellation. `Box(resultType)` produces the ordinary Alternative
at a generic boundary. Checked source lowering owns each operation's source site;
it must not fuse away cancellation, evaluation ordering or absence diagnostics.

`NewIntCompareFunction` and `NewFloatCompareFunction` accept raw typed bodies.
Those bodies own generated tracing and cleanup. The constructor installs ordinary
`Body` and guarded `IntCompare`/`FloatCompare` entries, with one source admission,
depth guard, source-return handling and cancellation delivery. Profiling falls
back through the ordinary source wrapper before typed admission. Passing an
already guarded body would double admission and is invalid.

`ListSorted` copies storage and uses typed comparator entries when available.
Arbitrary callbacks box once per element in temporary sorting storage, avoiding
boxing at every comparison. `ListSortInPlace` captures backing and swaps it in
place, preserving identity and mutation/reallocation semantics; an arbitrary
callback reads live captured cells and cannot use a cached mirror.

The natural primitive runtime order is numeric for Int, false before true for
Bool, and lexical UTF-8 byte order for String. Float puts NaNs before non-NaNs,
orders infinities numerically, and treats signed zeros as equal. Stable sorting
retains equal values' order and zero/NaN bits. A missing comparator for other
element kinds faults. The source declarations determine where comparator
omission is available; this ABI does not itself add source operations.

Large-literal emission is separately owned by #147 and still needs these
constructors. Typed source access/comparator lowering is separately owned by #87.
The [measurement evidence](https://github.com/manuscript-lang/manuscript/blob/main/scripts/bench-lists/typed-storage.md) separates
runtime improvements from those compiler dependencies.
