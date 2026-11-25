# net/url moved from C to Manuscript (2026-11-25)

Change: the seven `msstd_url_*` natives (`runtime/std/url*.c`, 1,244 lines of C) became `stdlib/net/url.ms`. Proposal: [pure codecs in Manuscript](../../../design/proposals/pure-codecs-in-manuscript.md).
Baseline: `4ebec175`, built in a separate worktree. After: this branch. Same program, both builds from the same preset, same shared 4-core Linux x86-64 VM, no other build running, 15 alternating runs each, 100000 rounds over three URLs (`parse` of each, or `format` of each parsed URL). Wall time in ms for the whole run; min and median.

| operation | before (C) min / median | after (Manuscript) min / median | ratio (min / median) |
| --- | --- | --- | --- |
| parse | 284 / 301 | 341 / 367 | 1.20 / 1.22 |
| format | 253 / 269 | 314 / 342 | 1.24 / 1.27 |

Instruction counts (`valgrind --tool=callgrind`, 3000 rounds, the same inputs): parse 110.9M before, 117.7M after (1.06x); format 89.2M before, 103.4M after (1.16x). `encode_component` is faster than the C (about 0.76x the instructions).

Output check: `projects/url_oracle` replays 3,466 cases (parse, format, resolve, component decode and encode, query parse and format, valid and invalid) recorded from the C code; every output and error kind is identical.

What closed the gap, found by callgrind and cache simulation, not by guessing: the first port was 1.45x. Parse and format built records of a dozen byte buffers, so cost sat in allocations, copies and stores of large records, not in the byte loops (those compile to a tight loop without bounds checks). Fixes in the port: no literal-to-bytes allocation for comparisons, `Bytes.get` as source so it inlines, exact-fit copies in `ms_bytes_from_span`, one builder for `render`, fewer record copies (`go_url` fills a `var` record), and views instead of copies where the value is only read.

Reading: the remaining 20 to 27% is record building (stores) and `to_bytes` of the empty buffers in `new_parts`. A cheaper empty `Bytes` and in-place record construction in the compiler would close it; neither is in this change.
