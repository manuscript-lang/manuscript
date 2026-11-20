[Wiki](../index.md) › [Runtime](index.md)

# JSON parsing is yyjson, and the error text is its text

Decision: the owner chose to vendor yyjson and swap the scanner for it (2026-11-20, after a measurement showed its error positions match the hand-written scanner's only about half the time). The syntax error of `parse` is `line L, column C: <yyjson reason>`; the reasons and positions are yyjson's, so a yyjson upgrade can change them.

Apply when: changing `runtime/std/json_scan.c`, upgrading yyjson (`runtime/third_party/yyjson`, version in `VERSION` and `tools/repo-check/licenses.ms`), or writing a test that expects JSON error text.
Evidence: [scanner](../../runtime/std/json_scan.c), [C test](../../runtime/tests/json_test.c) (`test_error_text`), [conformance](../../tests/conformance/fixtures/e2e/accept/library-errors.ms).
Verify: `json_test` under ASan/UBSan, `--id json` conformance, and `e2e/accept/library*`.

- The scanner copies the text into a buffer with `YYJSON_PADDING_SIZE` zeroed bytes after it and reads with `YYJSON_READ_INSITU | YYJSON_READ_NUMBER_AS_RAW`: yyjson decodes every string in place, so each string, key and number is a span of that buffer. A parsed document keeps the buffer as its text (no per-value copy); the tree builder lets it go. Uninitialized padding made reads flaky, so keep it zeroed.
- yyjson allows repeated keys, so the walker rejects them before the sinks see an object (pairwise up to 12 members, hashed beyond), with the position of the repeated key. A syntax error now outranks a depth or value budget, because the whole text is parsed before the budgets apply.
- Measured against the hand-written scanner (end to end, `msstd_json_parse` of a 12 MB document, median of 9): records about 5% faster, number-heavy arrays about 30% slower. A speed claim about JSON parsing needs a dated `bench/perf/` run, not these numbers.
