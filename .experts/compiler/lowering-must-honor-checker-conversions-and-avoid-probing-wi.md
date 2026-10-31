[Wiki](../index.md) › [Compiler and build](index.md)

# Lowering must honor checker conversions and avoid probing with side effects

Verified: checking can attach an implicit conversion (for example Optional wrapping of a plain argument) while the expression keeps its payload type. A lowering fast path that reads the raw expression instead of the converted argument stores the wrong representation, as a direct list call once did (`List[Int?]` held a bare Int and crashed). Error and Result widening composes with the Optional wrapper and stays in general expression lowering.

Verified: choose a lowering path before lowering its operands. Lowering mutates generator state (source markers, temporaries) even when its result is discarded, so an eligibility probe that lowers operands and then abandons them breaks exact-once invariants. Eligibility checks must return without lowering on an ineligible path. Keep the invariant assertion and an independent baseline rather than dropping unprinted markers.

Apply when: adding a lowering fast path, a direct call, or an optimization that tries one form then falls back.
Evidence: [lowering contract](../../documentation/contributing/compiler/lowering/evaluation-order.md), [Optional argument fixture](../../tests/e2e/testdata/accept/optional-arguments.ms), [collection conversion fixture](../../tests/e2e/testdata/accept/direct-collection-conversions.ms).
Verify: a plain value passed to an Optional parameter inside a list call executes, and operands run once in written order.
