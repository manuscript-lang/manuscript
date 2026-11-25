# Pure codecs in Manuscript

* Status: **Stages 1 and 2 implemented** (2026-11-25, `4ebec175`); stages 3 to 5 proposed
* Authors: Claude
* Implementation: `net/url` (stage 1): [result](../../bench/perf/pure-utilities/results-2026-11-25-url-in-manuscript.md); `html_entity` (stage 2): [result](../../bench/perf/pure-utilities/results-2026-11-25-html-entity-in-manuscript.md), which also found and fixed a compiler gap (constant lists rebuilt on every read)
* Direction: Chinmay, "we'll do that last, first focus on the c side"; standing rule "prefer Manuscript: C holds small, general runtime primitives".

## Summary

- Problem: pure text codecs (URL, HTML entities, base64/hex, JSON text, bignum text) are C in `src/runtime/std/`; they touch no OS, and each is a second implementation of something Manuscript can express.
- Change: port one library per stage into `src/stdlib/`, each against a corpus recorded from the C code first, each gated on a measured speed target. A port that misses its target is a compiler bug: the gap is fixed at its root in the compiler, never by keeping C or special-casing the library.
- Decision requested: none (internal; no language or API change). Stage 1 is built after review.

## Motivation

- C in `src/runtime/std/` that is pure data in, data out: `url*.c` 1,244 lines, `html_entity.c` 757, `encoding.c` 426, `json_*.c` about 2,100, `bigint.c`/`bignum.c`/`decimal.c` about 1,700. Libraries that need the OS (fs, net, process, time, crypto, tls, http) are out of scope.
- The path, HTML tokenizer, CSV, XML, template, PEM, MIME and ChaCha/BLAKE2 ports are done and meet the speed rule ([path](../wiki/stdlib-design/path-text-is-manuscript-and-only-the-glob-matcher-stays-native.md), [html](../wiki/benchmarks-and-performance/a-ms-html-parser-matches-rust-with-int-tables-and-a-flat-tree.md)). The recipe is proven; these libraries are what is left.
- Baseline for stage 1 (measured, `4ebec175`, release `ms`, Linux x86-64, 3 runs): 600,000 rounds of `parse` + `format` + `encode_component` over three URLs take 1,507 to 1,535 ms, about 2.5 us a round.

## Detailed design

**Order.** `net/url` first: self-contained (`http_url.c` uses curl's parser, not `url_parse.c`), 92 lines of `.ms` over seven externs, an existing suite (`projects/url_suite`, `stdlib/url.ms`). Then `html_entity` (the one native left in `data/html.ms`), `encoding`, `json` text scan/write, last bignum and decimal. Each stage is its own PR and may stop the series.

**Per stage, in order.**
1. Record a corpus from the C implementation: generated and hand-picked inputs for every extern (valid, invalid, boundary, invalid UTF-8, NUL), stored as a data file next to a replay test, as `path_oracle` does.
2. Port to `.ms` using the performance rules already recorded: Int tables and constants, byte scans (`Bytes.index_of_byte`), no per-byte allocation, no string `match` in hot paths.
3. Replay the corpus on the `.ms` code; every output and every error text must match.
4. Benchmark against the recorded C baseline (`bench/perf/pure-utilities/`, many runs, median). Target: within 1.25x of C on common inputs and no worse than 2x on any case. Over target means find the compiler cause (for example a missing fusion or a copy) and fix it at the root as part of the stage; the C stays until the target is met.
5. Delete the C file, its externs in `stdlib/internal/*.ms`, its header, tests and `src/layers.txt` entries only after 3 and 4 hold.

**What stays C.** Anything a C caller also uses (a library with C callers outside its own files, such as `json.h` with 25 includers, moves only when those callers move or are given a small primitive), tables too large to be worth source (html entity table, if the measured cost of a source table is above target), and the glob matcher (shared with `fs.glob`).

**Risks.** The checker's cost on large literal tables; the one-owner model forcing `.clone()` in token buffers (known from the HTML port); behavior drift on invalid input, which the corpus pins; a gap that needs a language change rather than a compiler fix, which goes to Chinmay as a choice.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/stdlib/net/url.ms`, later `data/*.ms` | the port | recorded corpus replay, existing suites |
| `src/stdlib/internal/net.ms` etc. | externs removed | `ms check`, `docs-check` |
| `src/runtime/std/url*.c` etc. | deleted | `ctest`, `lint`, `conform` |
| `bench/perf/pure-utilities/` | dated section per stage | before/after median |
| compiler (`lower`, `opt`) | only for root-cause perf fixes found by a stage | `conform`, perf run |

## Alternatives considered

- Do nothing: keeps about 6,000 lines of C that `.ms` can say in fewer lines (the url port should be about 600), and leaves "prefer Manuscript" unmet for the largest remaining pieces. Speed and behavior stay unchanged, so the benefit is code removed and every future user of the compiler measured on real library code, not speed.
- Keep a slow library in C: rejected by the owner; a gap is compiler work.
- Port everything in one PR: unreviewable, and one slow library blocks the rest.
- Port without a recorded corpus: the HTML and path ports show drift on invalid input is the main risk; the corpus is what makes the C deletion safe.
