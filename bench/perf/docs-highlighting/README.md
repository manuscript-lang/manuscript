# Documentation grammar preparation — 2026-11-12

Baseline: `37a14ba5797bed73a66d1350bee03d2238c63a20`. Candidate is this directory's commit. Run `node bench/perf/docs-highlighting/run.cjs <baseline>`. The harness loads the baseline tokenizer from Git and the actual candidate's private preparation helper without booting a browser or simulating a DOM. The public `tokenize(source, grammar)` export remains unchanged.

Linux x64, Node v24.19.0, Intel Xeon Platinum 8573C. Ten warmup pairs, then 31 alternating samples; each batches 100 single-short pages, ten actual `named-types.md` pages, or four long fences. Grammar preparation is included once per page. Outputs are checked for exact token equality; timed outputs contribute a checksum. Raw samples are in `results-2026-11-12.json`.

Median per page: single short fence 0.04226 to 0.04174 ms (neutral); actual 14-fence page 1.492 to 0.951 ms; single long fence 8.306 to 7.319 ms. An earlier experimental version had an inconclusive 3.4% long-fence slowdown; five longer confirmation runs did not reproduce it, and these numbers measure the final implementation, not that earlier prototype.

Compile the immutable page grammar once, but retain a fresh lexical stack, cursor and tokens for each fence. Tests cover exact existing token behavior, unfinished strings/comments followed by other fences, Unicode/CRLF and independence of two prepared grammars. These pure-function results do not establish browser page-load or DOM performance. Shared-host sub-millisecond differences are not a performance guarantee.
