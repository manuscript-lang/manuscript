# Component decoder follow-up, 2026-10-31

This follows the four rejected decoder candidates in the [initial utility
report](README.md). It specializes only `decode_component`; the shared byte
parser, URL parser, query codec and network APIs are unchanged.

The baseline is actual merged main
`28946f9c42b48eff4b79a01edc2130bd92c82133`, which contains the calendar fixes and
POSIX path PR #2145. Main renamed the internal `gourl` module to `parser` without
changing its bytes. The benchmark recorder and old-decoder test reference use
the new filename; all historical recorders and source identities remain intact.

## Algorithm and compatibility

The previous wrapper uses a general byte unescaper, then validates UTF-8.
The candidate scans a literal prefix directly. With no percent sign,
the input is already valid UTF-8 and needs only an owned copy. Otherwise it
validates every escape in the suffix before allocation, reserves the same input
length, copies the literal prefix once and decodes the suffix. The existing
UTF-8 conversion checks the complete result.

This removes general mode/plus bookkeeping and avoids per-byte decoding work on
the literal prefix. These are source changes; measurements do not establish
which change explains each timing difference or attribute prior failures to
iterator setup. Dense escapes still need two suffix passes to preserve the
zero-allocation malformed-input behavior.

Literal plus, NUL, mixed Unicode, nonrecursive escapes, both hex cases, truncated
escapes and invalid decoded UTF-8 retain their previous results. `%FF%zz` and
`%FF%` explicitly verify that a decoded UTF-8 error in a valid prefix does not
skip later malformed-escape validation or introduce an allocation.

## Protocol and coverage

Use the initial suite's CPU-0 interleaving, checked output fields/errors and
checksums, pinned Rust/Cargo 1.99.1, explicit MS Release settings and native
release archives. The fixed compiler is rebuilt from merged main before applying
this patch and builds both producers. Setup precedes timers. Every output/error
is checked inside timing. All producer permutations are balanced; no samples
are discarded.

The current inventory has 80 URL cases, adding the invalid-UTF-8 prefix followed
by a malformed escape to the earlier 79. All 72 path controls remain. The URL
baseline is merged main 28946f9; the cumulative path baseline is pre-path main
81b804d. Both use the same merged-main compiler. Path programs built against
merged main and the URL candidate are byte-identical, so the URL change does
not change those measured executable images.

The focused precursor used unchanged URL source at 09e0 with the same fixed
main-81 compiler for both archives: 507 balanced observations, 1,680 smoke
observations and 432 direct allocation observations. All 13 paired timing
medians improved, but individual slower pairs remain; this alone is insufficient
for retention.

Fresh native controls pass 1,008 observations across 126 path/decode cases.
Allocation/reallocation calls, requested/peak bytes and final live bytes match
baseline in every case, including malformed input after valid escapes and invalid UTF-8 prefixes.
These are direct native helper observations, not MS runtime/RSS claims.

## Results at the pinned merged base

The complete runtime replay retains **15,200 observations**: 7,200 cumulative
path controls and 8,000 URL observations. Every trial, permutation, output/error,
checksum and source/binary identity passes independent review. A separate
375-observation confirmation checks five small/unchanged controls.

| Component workload | Before ns/op | After ns/op | Paired after/before | Paired after/Rust |
| --- | ---: | ---: | ---: | ---: |
| Safe ASCII |60.068|51.252|0.866|0.115|
| Mixed Unicode and escape |70.681|67.000|0.955|0.145|
| Long safe |3154.514|1653.384|0.525|2.158|
| Dense escapes |8821.507|7781.612|0.890|1.486|
| Sparse escape |6648.691|3460.648|0.527|1.365|
| Tail escape |6651.472|1776.703|0.268|2.097|
| Early malformed escape |31.876|29.582|0.924|0.059|
| Late malformed escape |2406.055|1250.564|0.515|1.559|
| Late invalid UTF-8 |6296.747|1400.175|0.223|1.636|

Times are separate medians; ratios are medians of same-trial pairs. Long safe,
sparse, tail and late-error inputs improve in every pair; dense escapes improve
in 22/24. Residual Rust ratios 1.365–2.158 remain on these large cases; this does
not establish parity. The streaming Rust error control may allocate before a
malformed escape; the native implementation preserves zero allocation there.

All adverse full-run medians are retained: encode empty 1.003, safe 1.019,
Unicode 1.004; decode plus 1.011; parse-error empty 1.015, host-colons 1.017,
host-space 1.003, early-control 1.009, early-percent 1.031, late-UTF8 1.0002.
Every adverse interquartile range crosses 1. The longer controls yield:

| Control | Paired after/before | A/A | Faster/24 |
| --- | ---: | ---: | ---: |
| Encode safe |0.990|0.994|13|
| Decode plus |0.997|1.018|12|
| Parse-error empty |1.012|0.984|10|
| Parse-error host-colons |1.004|1.003|12|
| Parse-error early-percent |0.993|0.994|14|

Empty URL-error parsing has a **0.884 ns median paired increase**; it is not
claimed flat. No material common-path regression is demonstrated, and independent
review supports retaining this pinned runtime experiment with that disclosure.

The merged path gains also persist: extension ratios 0.036–0.973 and normalization
0.782–0.978; empty parsing 0.995 and long-basename parsing 0.977. The earlier
marginal empty-path cost does not persist here. This is a separate checkpoint,
not a reason to erase the earlier observation. All other adverse parse
interquartile ranges cross1. Remaining parse/Rust gaps are recorded in the
initial report and raw data.

## Integration follow-through

Runtime results above use the exact pinned main-289 compiler, native archives
and executable identities. No build-time speed claim is made. Newer main added
backend/cache mechanisms outside this lane and retired the earlier calendar
benchmark directories. Retired sources/results remain reachable through their
immutable commits; this change does not restore them. Latest-main reconciliation,
ordinary current-head validation and normal CI remain publication prerequisites.
