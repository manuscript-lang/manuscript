[Wiki](../index.md) › [Compiler and build](index.md)

# Evaluation order: receivers and operands are captured before later calls

Verified: a plain local read is not ordered against a later call unless the lowering orders it. A right-hand `match` or an index expression can reassign the receiver or the left operand local, so the receiver and each operand must be captured in written order before the operation that uses them, and prerequisites stay inside their short-circuit, match, and loop regions. Hoisting them changes source behavior.


Apply when: removing bound-call wrappers or lowering expressions to direct operations.
Evidence: [evaluation order](../../documentation/contributing/compiler/lowering/evaluation-order.md), [receiver reassignment regression](../../tests/conformance/fixtures/e2e/accept/collection-call-order.ms), [operand order](../../tests/conformance/fixtures/e2e/accept/operand-order.ms).
Verify: a list receiver initially holding 7 still yields 7 when its index expression reassigns the local to a list holding 9.
