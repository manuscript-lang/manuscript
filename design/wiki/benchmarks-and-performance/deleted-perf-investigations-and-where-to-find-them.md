[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Deleted perf investigations and where to find them

Decision (Chinmay, 2026-11-25): `bench/perf/` holds only the groups of the one suite ([`groups.txt`](../../../bench/perf/groups.txt)). Each finished investigation below was deleted in the commit after `48b25d38`, once its finding was recorded in a wiki page or proposal that cites it. Read one with `git show 48b25d38:bench/perf/<name>/README.md` (a dated page is the file itself), or follow its permalink. Dated whole-suite refreshes (`baseline-*`, `results-*`, `perf-bash-*`) are superseded by [`results.md`](../../../bench/perf/results.md) and the group pages.

When a perf change needs a baseline, add a dated section to the group's results; do not start a new folder. A one-off probe that changes a decision gets a wiki page with its numbers, not a folder.

| Name | Title or topic |
| --- | --- |
| [`ascii-decode`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/ascii-decode) | Rejected ASCII decoding experiment, 2026-10-31 |
| [`baseline-2026-10-27.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/baseline-2026-10-27.md) | Manuscript-only baseline, 2026-10-27 |
| [`baseline-2026-10-28.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/baseline-2026-10-28.md) | Manuscript-only baseline, 2026-10-28 |
| [`binary-words`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/binary-words) | Fixed-width binary words — 2026-11-12 |
| [`binding-flags`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/binding-flags) | Binding facts across repeated compiler checks — 2026-11-05 |
| [`bytes-index`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/bytes-index) | Byte search: 2026-10-31 |
| [`call-candidates`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/call-candidates) | Call candidate resolution benchmark |
| [`checker-inference-resolution`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/checker-inference-resolution) | Checker argument-inference benchmark |
| [`checksum-dependency`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/checksum-dependency) | Shorten the CRC-32 carried dependency |
| [`checksums`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/checksums) | Checksums and hashes |
| [`clone-costs`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/clone-costs) | Clone costs |
| [`close-parts`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/close-parts) | Closing what containers and fields own: no cost without resources |
| [`closure-capture`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/closure-capture) | Closure captures |
| [`codec-encoding`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/codec-encoding) | Hex and padded Base64 encoding against C |
| [`codegen-2026-11-12.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/codegen-2026-11-12.md) | Generated-code gaps against Rust, 2026-11-12 |
| [`collections-round1`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/collections-round1) | collections-round1 |
| [`collections-round2`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/collections-round2) | collections-round2 |
| [`collections-round3`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/collections-round3) | collections-round3 |
| [`collections-round4`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/collections-round4) | collections-round4 |
| [`combinations`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/combinations) | Combination traversal |
| [`compile`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/compile) | Compile time of the compiler |
| [`compile-scaling`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/compile-scaling) | Compile time and binary size at scale, 2026-11-14 |
| [`compile-stress`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/compile-stress) | Compile-time stress |
| [`control-flow-conditions`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/control-flow-conditions) | Nonreturning condition reachability — 2026-11-10 |
| [`cranelift-survey-2026-11-13.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/cranelift-survey-2026-11-13.md) | Cranelift output survey, 2026-11-13 |
| [`crypto-signatures`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/crypto-signatures) | Signature and key-agreement speed |
| [`csv-quote-search`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/csv-quote-search) | CSV quote detection |
| [`debug-variables-2026-11-15.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/debug-variables-2026-11-15.md) | Parameter variables in debug info: cost on the LLVM release backend (2026-11-15) |
| [`deque-rotation`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/deque-rotation) | Deque rotation directions |
| [`diff-context`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/diff-context) | Unified diff context marking |
| [`dns-localhost`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/dns-localhost) | `lookup("localhost")` |
| [`docs-highlighting`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/docs-highlighting) | Documentation grammar preparation — 2026-11-12 |
| [`effect-reachability`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/effect-reachability) | Effect reachability investigation, 2026-11-10 |
| [`everyday-round5`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/everyday-round5) | Everyday code round 5 |
| [`exits-2026-11-24.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/exits-2026-11-24.md) | Cost of exits on by default (2026-11-24) |
| [`float-parse-ascii`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/float-parse-ascii) | Rejected Float ASCII-scan optimization |
| [`for-each-var-2026-11-06.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/for-each-var-2026-11-06.md) | `for_each` with a `var` callback, 2026-11-06 |
| [`formatter-flow`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/formatter-flow) | Formatter flow and suffix controls |
| [`formatter-validation-2026-11-12`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/formatter-validation-2026-11-12) | Formatter validation parse reuse — 2026-11-12 |
| [`generic-bound-order`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/generic-bound-order) | Generic bound declaration order — 2026-11-10 |
| [`heap-parity`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/heap-parity) | Heap parity with Rust, 2026-11-12 |
| [`html`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/html) | HTML parse |
| [`http-tail`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/http-tail) | HTTP tail latency |
| [`image-codecs`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/image-codecs) | Image codec speed |
| [`image-rotations`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/image-rotations) | Image rotations |
| [`index-of`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/index-of) | `List[String].index_of` |
| [`integer-parse-radix`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/integer-parse-radix) | Rejected integer radix parsing optimizations |
| [`itertools-cycle`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/itertools-cycle) | itertools-cycle |
| [`json-escape-runs`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/json-escape-runs) | Rejected JSON escape-run experiment, 2026-10-31 |
| [`json-library`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/json-library) | JSON float writer controls, 2026-10-31 |
| [`kernel-parity`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/kernel-parity) | Paired kernels against Rust, 2026-11-12 |
| [`list-distinct`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/list-distinct) | Avoid redundant membership checks in Set algebra |
| [`lsp`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/lsp) | Local formatter and LSP performance controls |
| [`lsp-outline`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/lsp-outline) | Document-outline suffix scans |
| [`lsp-semantic`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/lsp-semantic) | Ordered semantic-token positions |
| [`map-runtime-audit`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/map-runtime-audit) | Runtime Set intersection benchmarks |
| [`mir-survey-2026-11-14.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/mir-survey-2026-11-14.md) | MIR and translation survey, 2026-11-14 |
| [`module-inputs`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/module-inputs) | Module-loader input tracking |
| [`native-fallbacks`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/native-fallbacks) | Native fallbacks against Manuscript twins, 2026-11-12 |
| [`optional-literal-context`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/optional-literal-context) | Optional sized literal context: frontend qualification |
| [`parser-speculation`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/parser-speculation) | Failed type-argument speculation — 2026-10-31 |
| [`parser-suffix`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/parser-suffix) | Parser type-suffix construction — 2026-10-31 |
| [`path-resolve`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/path-resolve) | POSIX path resolution |
| [`perf-bash-2026-11-03.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-03.md) | Perf bash, 2026-11-03 (stdlib, data structures, programs) |
| [`perf-bash-2026-11-09.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-09.md) | Perf bash, 2026-11-09 |
| [`perf-bash-2026-11-14-collections.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-14-collections.md) | Perf bash, 2026-11-14: collections |
| [`perf-bash-2026-11-18-concurrency.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-18-concurrency.md) | Perf bash, 2026-11-18: concurrency and I/O throughput |
| [`perf-bash-2026-11-18.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-2026-11-18.md) | Perf bash, 2026-11-18: workloads and standard library hot paths |
| [`perf-bash-memory-and-size-2026-11-18.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-memory-and-size-2026-11-18.md) | Perf bash, 2026-11-18: peak memory, startup and binary size |
| [`perf-bash-paths-urls-2026-11-18.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-paths-urls-2026-11-18.md) | Perf bash, 2026-11-18: paths, URLs and globs |
| [`perf-bash-text-2026-11-18.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/perf-bash-text-2026-11-18.md) | Perf bash, 2026-11-18: text and data processing |
| [`permutations-zero`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/permutations-zero) | Zero-size permutations |
| [`pipe-chain`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/pipe-chain) | Pipe chain across scheduler threads |
| [`pipe-pipeline`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/pipe-pipeline) | Pipe pipeline across scheduler threads |
| [`priority-queue-singleton`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/priority-queue-singleton) | Rejected singleton PriorityQueue experiment — 2026-10-31 |
| [`pure-utilities`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/pure-utilities) | Pure utility comparisons |
| [`refcount-removal-2026-11-03.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/refcount-removal-2026-11-03.md) | Refcount removal, 2026-11-03 |
| [`regex-search`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/regex-search) | Regex search over a large text |
| [`report-route`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/report-route) | Program-map route queue — 2026-11-12 |
| [`representative`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/representative) | Representative compiler and program measurements |
| [`results`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/results) | results |
| [`results-2026-11-05.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/results-2026-11-05.md) | Benchmark refresh, 2026-11-05 |
| [`results-2026-11-09.md`](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/results-2026-11-09.md) | Kernels against C with bounds checks, 2026-11-09 |
| [`rt-hot-moves`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/rt-hot-moves) | Inline `first` and `last` |
| [`rt-hot-retired`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/rt-hot-retired) | Retiring `ms-rt-hot`: speed against `main` |
| [`set-empty-relations`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/set-empty-relations) | Empty-right Set disjointness |
| [`set-membership`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/set-membership) | Integer Set membership layout |
| [`small-promises`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/small-promises) | Many small promises across threads |
| [`statistics-correlation`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/statistics-correlation) | Correlation accuracy guard cost |
| [`string-lines`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-lines) | String line splitting |
| [`string-micro`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-micro) | String micro-benchmarks |
| [`string-normalization-rollback`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-normalization-rollback) | Integration normalization regression: completed evidence and open correction |
| [`string-normalize-ascii`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-normalize-ascii) | ASCII identity normalization and lazy Unicode input |
| [`string-normalize-stream`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-normalize-stream) | Lazy input decoding for Unicode normalization |
| [`string-pass`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/string-pass) | String pass |
| [`structural-gaps`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/structural-gaps) | Structural gaps |
| [`template-numbers`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/template-numbers) | Exact template numeric comparisons |
| [`time-format`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/time-format) | Timestamp format output buffer |
| [`time-format-numeric`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/time-format-numeric) | Numeric timestamp tokens |
| [`time-shift`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/time-shift) | Timestamp shift arithmetic |
| [`timestamp-parse`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/timestamp-parse) | Timestamp parser bounds |
| [`toml`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/toml) | TOML parse against Rust |
| [`toml-classification`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/toml-classification) | TOML table-array classification |
| [`toml-control-scan`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/toml-control-scan) | TOML control admission, 2026-10-31 |
| [`toml-quoting`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/toml-quoting) | TOML control-escape performance |
| [`tool-speed`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/tool-speed) | Tool speed on large inputs, 2026-11-18 |
| [`tooling-preflight-2026-10-31`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/tooling-preflight-2026-10-31) | Matched tooling performance preflight — 2026-10-31 |
| [`url-parents`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/url-parents) | URL parent-reference resolution |
| [`xml-delimiters`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/xml-delimiters) | XML delimiter preparation — 2026-11-12 |
| [`xml-stringify`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/xml-stringify) | XML stringify child inspection |
| [`yaml-append-escapes`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/yaml-append-escapes) | Rejected direct YAML escape append, 2026-10-31 |
| [`yaml-folding`](https://github.com/manuscript-lang/manuscript/tree/48b25d38/bench/perf/yaml-folding) | Folded YAML plain scalars |
