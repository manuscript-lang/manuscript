[Wiki](../index.md) › [Compiler and build](index.md)

# Lowering must honor checker conversions and avoid probing with side effects

Verified: checking can attach an implicit conversion (for example Optional wrapping of a plain argument) while the expression keeps its payload type. A lowering fast path that reads the raw expression instead of the converted argument stores the wrong representation, as a direct list call once did (`List[Int?]` held a bare Int and crashed). Error and Result widening composes with the Optional wrapper and stays in general expression lowering.

Apply when: adding a lowering fast path, a direct call, or an optimization that tries one form then falls back.
Evidence: [lowering contract](../../documentation/contributing/compiler/lowering/evaluation-order.md), [Optional argument fixture](../../tests/conformance/fixtures/e2e/accept/optional-arguments.ms), [collection conversion fixture](../../tests/conformance/fixtures/e2e/accept/direct-collection-conversions.ms).
Verify: a plain value passed to an Optional parameter inside a list call executes, and operands run once in written order.

Lesson (callback element mutation, 2026-11-06): `List.for_each` and `Map.for_each` declare their callback `fn(var T)` / `fn(T, var U)`; the checker rule is general and type-driven (`callback_changes_receiver`: a declared `var` callback position whose type is a receiver type argument, filled by a function that takes it `var`), and `call_modes` then treats the receiver as changed. Lowering passes element addresses (`ListAddrU`, a map entry's value pointer) to every such callback. A function that only reads (`Info.function_source`) is passed as written, unadapted (`NArg.reader`, `expr_unfit`), and the loop hands it values: the adapter made `for_each` 2.7 times slower. An adapter that wraps an owned closure must take it over (or leave it to the statement's temps when the closure is scoped), or the verifier reports "owned value never released". A method value of such a method from a place is rejected (`takes_element_mutator`): it would let a changing callback reach a receiver the checker never saw as changed. Interface dispatch does not apply the rule.
