[Wiki](../index.md) › [Runtime](index.md)

# The JSON scanner reads eight bytes at a time

Decision: the owner chose to keep our own scanner over vendoring yyjson (2026-11-20) and to speed it up with yyjson's techniques; the vendored experiment (#4851) was reverted (#4863). Its numbers are in `bench/perf/json/results.md` as the target.

Apply when: changing `src/runtime/std/json_scan.c` or the document builder `src/runtime/std/json_doc.c`, or adding a new byte scan to the runtime.
Evidence: [scanner](../../src/runtime/std/json_scan.c), [document builder](../../src/runtime/std/json_doc.c), [boundary test](../../src/runtime/tests/json_test.c) (`test_word_boundaries`), [results](../../bench/perf/json/results.md).
Verify: `json_test` under ASan/UBSan and `--id json` conformance, then the same-process comparison against the previous scanner on twitter, citm_catalog and canada.

- Strings, runs of spaces and runs of digits are read as `ms_load64` words with the zero-byte tricks; only the lowest flagged byte of a word is trusted (`ctz`), which is exact even where a carry corrupts the bytes above it. A scan that reads a word needs `pos + 8 <= length`; the tail goes a byte at a time. Every offset against a word boundary is covered by `test_word_boundaries`.
- Instruction counts (`valgrind --tool=callgrind --toggle-collect=msstd_json_parse`) are the steady measure on a noisy machine: wall-clock runs on the shared cloud cores varied by 10% between runs. Use best-of-N MB/s for the headline and the counts to judge a change.
- What is left after the scan is the document builder (nodes, pending lists, the copy of the text), so a faster scanner moves the standard documents less than the scan-only numbers suggest.
