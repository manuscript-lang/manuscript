[Wiki](../index.md) › [Runtime](index.md)

# CSV writer defaults can erase a single empty field

Verified: a naive CSV writer emits the same bare line ending for zero fields and one empty field, while a reader skips blank lines. Manuscript must explicitly quote the sole empty field to retain that row, including the quotes in the output budget. Empty rows still serialize as skipped blank lines; changing reader behavior would alter that contract.

Apply when: changing CSV adapters or relying on a codec's round-trip behavior.
Evidence: [called CSV regressions](../../tests/e2e/testdata/stdlib/csv.ms), [CSV crate](../crates/ms-std-csv/src), [CSV contract](../../stdlib/json.ms).
Verify: round-trip consecutive single empty fields with LF/CRLF and alternate delimiters; check distinct empty-row output and exact byte, row, and cell budgets.
