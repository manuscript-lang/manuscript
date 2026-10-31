[Wiki](../index.md) › [Language](index.md)

# Compound assignment, counting ranges, and redundant labels

Decision: the user asked to add `+= -= *= /= %=`, a step-1 `range(start, end)`, and removal of redundant argument labels (October 2026 proposal `structural-syntax`), reversing the earlier MS1000 rejection of compound assignment. A compound statement means `target = target op (value)` with the written operator kept for formatting; the receiver of a field target must be names only so it is read once.

Apply when: changing assignment syntax, `for` lowering, `@std/collections.ms` factories, or the formatter.
Evidence: [native fixture](../../tests/e2e/testdata/accept/compound-assignment.ms), [range fixture](../../tests/e2e/testdata/stdlib/collections.ms).
Verify: `total -= a - b` subtracts the whole right side, a call or index receiver is rejected, a `range` bound mutated in the body does not change the count, and `--drop-labels` is idempotent and skips labels that select another parameter.
