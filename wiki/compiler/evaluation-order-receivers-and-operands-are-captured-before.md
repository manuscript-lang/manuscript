[Wiki](../index.md) › [Compiler and build](index.md)

# Evaluation order: receivers and operands are captured before later calls

Verified: a plain local read is not ordered against a later call unless the lowering orders it. A right-hand `match` or an index expression can reassign the receiver or the left operand local, so the receiver and each operand must be captured in written order before the operation that uses them, and prerequisites stay inside their short-circuit, match, and loop regions. Hoisting them changes source behavior.


A changing place is selected by an ordinary checked receiver-first read, not an index-only
prepass. An earlier bounds or missing-key fault must precede later indices and arguments.
Retain only the fitted index values along its receiver chain through the final writeback,
with module-qualified identities for defaults. Do not retain projections or storage pointers
across sibling calls. Retire selections on abandoned calls and discarded-copy paths too.
Resource entry closes stay in the original owner storage before mutation; intermediate
map clearing must not retire the final mutation's selection.

Open lifetime gap: retaining a borrowed key header does not retain its source owner if a later
argument replaces that source ([#2843](https://github.com/manuscript-lang/manuscript/issues/2843)).
Do not silently add blanket key clones or suppress implicit-copy/ownership checks to hide it.

Apply when: removing bound-call wrappers or lowering expressions to direct operations.
Evidence: [evaluation order](../../documentation/contributing/compiler/lowering/evaluation-order.md), [receiver reassignment regression](../../tests/conformance/fixtures/e2e/accept/collection-call-order.ms), [operand order](../../tests/conformance/fixtures/e2e/accept/operand-order.ms).
Verify: a list receiver initially holding 7 still yields 7 when its index expression reassigns the local to a list holding 9.

Regression checks: [checked places](../../tests/e2e/testdata/accept/checked-place-evaluation.ms) and [resource places](../../tests/e2e/testdata/accept/resource-place-evaluation.ms).
