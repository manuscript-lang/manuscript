[Wiki](../index.md) › [Runtime](index.md)

# CSV writer defaults can erase a single empty field

Verified: a naive CSV writer emits the same bare line ending for zero fields and one empty field, while a reader skips blank lines. Manuscript must explicitly quote the sole empty field to retain that row, including the quotes in the output budget. Empty rows still serialize as skipped blank lines; changing reader behavior would alter that contract.


Apply when: changing CSV adapters or relying on a codec's round-trip behavior.
Evidence: [called CSV regressions](../../tests/conformance/fixtures/e2e/stdlib/csv.ms), [CSV implementation and contract](../../stdlib/data/csv.ms).
Verify: round-trip consecutive single empty fields with LF/CRLF and alternate delimiters; check distinct empty-row output and exact byte, row, and cell budgets.

Quote detection need not materialize every Unicode scalar: after validating the delimiter as one ASCII scalar, byte substring searches find quote, CR, LF and delimiter without changing Unicode matching. Inspect only the first scalar for the existing leading-whitespace rule, and retain the exact `\\.` special case. The CSV fixture covers near-matches, Unicode whitespace, alternate delimiters and exact output budgets. Performance evidence belongs in [the CSV quote-search suite](../../bench/perf/csv-quote-search/README.md).
