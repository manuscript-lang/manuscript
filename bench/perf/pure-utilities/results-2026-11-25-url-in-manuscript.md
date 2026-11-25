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

## 2026-11-25, later: parity work

The owner's rule is that a port matches C, not 1.2x. Same method and VM (31 alternating runs, 100000 rounds), wall ms, min / first quartile / median:

| operation | C | Manuscript | ratio (min / q1 / median) |
| --- | --- | --- | --- |
| parse | 290 / 298 / 333 | 298 / 304 / 355 | 1.03 / 1.02 / 1.07 |
| format | 246 / 254 / 272 | 257 / 268 / 298 | 1.04 / 1.06 / 1.10 |

Instructions (3000 rounds): parse 110.3M (C 110.9M), format 92.7M (C 89.2M). Branch mispredictions: parse 574k (C 692k).

What closed it, each a general fix or a port change found by the profiles:

- `String.to_bytes` of an empty string no longer calls the runtime (role `string_to_bytes` in `opt_strfast`: an empty string is the empty bytes, so `"".to_bytes()` folds to constants). `new_parts` made ten such calls per URL.
- A constant list of integer literals is a static view (`list.const.view`), so the byte-class table is one load, not a rebuilt list. `should_escape` is a table lookup: the branchy version mispredicted 23% more than C.
- `parse_parts` and `go_url` fill a `var` record instead of returning an optional record (a 248-byte copy each), `split_host_port` returns offsets, and `build_parts` views instead of copying.

Remaining gap: record building (stores) and the allocations of `Parts`, one per field.
