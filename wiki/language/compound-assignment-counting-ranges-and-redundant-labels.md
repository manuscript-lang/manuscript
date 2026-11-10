[Wiki](../index.md) › [Language](index.md)

# Compound assignment, counting ranges, and redundant labels

Decision: the user asked to add `+= -= *= /= %=`, a step-1 `range(start, end)`, and removal of redundant argument labels (October 2026 proposal `structural-syntax`), reversing the earlier MS1000 rejection of compound assignment. A compound statement means `target = target op (value)` with the written operator kept for formatting; the receiver of a field target must be names only so it is read once.

Apply when: changing assignment syntax, `for` lowering, `@std/collections/collections.ms` factories, or the formatter.
Evidence: [native fixture](../../tests/conformance/fixtures/e2e/accept/compound-assignment.ms), [range fixture](../../tests/e2e/testdata/stdlib/collections.ms).
Map entries (#3387): `m[line.sku] -= q` and `m[k] -= q` with a name, field-path or literal key work by cloning the key for the store (the plain desugar moved the owned key before the read borrowed it). That needed `.clone()` on scalar primitives, which return themselves, so a parse-time desugar does not need the key type.
Verify: `total -= a - b` subtracts the whole right side, a call or index receiver is rejected, a `range` bound mutated in the body does not change the count, and `--drop-labels` is idempotent and skips labels that select another parameter.
