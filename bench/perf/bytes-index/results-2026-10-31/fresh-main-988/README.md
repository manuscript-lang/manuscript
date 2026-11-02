# Fresh main 988 integration replay

The documentation conflict with main is resolved, preserving both independent
benchmark lessons. Local merge `58691f4e3e9143c47ddc5801902e9aba8a8633ab`
contains main `98854115f95bfeddbaa362382bfcff85c0499752` and the unchanged
word/vector byte-search patch. Main advanced again during this frozen comparison;
these numbers belong to this checkpoint, not an unmeasured later main.

Baseline and word archives were rebuilt serially in the same worktree. The
baseline runtime source matches the named main; the candidate differs only by
[the production patch](production.patch). Both states use fixed compiler SHA-256
`c0206ad63cab27353feb941a70d4f500dca2856beeb184e4cd98cf3b997a4a85`.
[Build records](build-record.json) identify all eight programs, sources,
archives, commands and exits. Companion metadata reports normal Release /
Cranelift; no stronger effective-backend claim or investigation is made.

All builds/checks finished before serial CPU-0 timing. Every producer's exact
identity, iterations, complete output guard, checksum and exit passed. The
[replay record](replay-record.json) validates unchanged programs and inputs
before/after. The complete suites are:

| Suite | Variants | Rounds | Cases | Raw rows |
| --- | --- | ---: | ---: | ---: |
| byte search | baseline, word, Rust memchr | all six permutations | 220 | 3,960 |
| line splitting | baseline, word | eight balanced rounds | 16 | 256 |
| normalization | baseline, word | eight balanced rounds | 100 | 1,600 |
| scalar reversal | baseline, word, Rust | all six permutations | 83 | 1,494 |

Two-state controls repeat rotations and their reversals twice. Three-state
controls place every variant equally in every position. Warmups are separate.
Medians, extrema and per-round paired differences/signs for **every case** are in
the four `*-paired.csv` files; the raw samples and original summaries remain in
each suite directory. Median ratios and median paired deltas are different
statistics. No equivalence or significance claim follows from a descriptive
threshold or a small number of pairs.

## Byte outcome and remaining costs

| Case | Baseline ns/op | Word ns/op | Rust ns/op | Word paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 MiB miss | 237,910.70 | 7,364.42 | 7,153.44 | -230,810.35 | 0/6 |
| 1 MiB last hit | 238,134.67 | 7,149.98 | 7,188.55 | -230,993.69 | 0/6 |
| offset 16, 4 KiB | 5.40 | 2.74 | see full data | -2.62 | 0/6 |
| offset 17, 4 KiB | 5.53 | 4.18 | see full data | -1.52 | 0/6 |

Long miss/last-hit speedups are about 32x/33x in this phase. All eight increased
byte medians remain explicit: seven second-byte hits cost a paired 0.26–0.39 ns,
six of six slower each; the one-byte miss costs 0.15 ns, six of six slower.
These are consistent tiny costs, not erased as noise. Tiny Rust calls include
opaque wrapper/guard overhead. Close large-case numbers do not establish
universal Rust parity.

## Full affected controls

The earlier 8dd 63-byte reversal flag does not recur at its original size here:
224.77→226.59 ns (+0.81% separate medians), paired -2.49 ns, two of six slower,
paired range -13.35…+8.75 ns. The original +6.63% observation, both repeats and
A/A remain in [the previous phase](../fresh-main-8dd/README.md); this later
checkpoint cannot erase that evidence or prove the operation unchanged.

All unfavorable observations remain. Ten of 16 line medians increase; the largest
is 65,536-byte-width LF input, +2.97%, paired +581.41 ns, five of eight slower.
Forty-seven of 100 normalization medians increase. The largest is early-Unicode
4 KiB NFC, +3.72%, paired +998.24 ns, five of eight slower; early-Unicode 4 KiB
NFKC is +3.17%, paired +1,410.70 ns, seven of eight slower. Fifty-nine of 83
reversal medians increase; the largest is mixed two-copy input, +3.17%, paired
+3.21 ns, four of six slower. Two-byte 4,096-copy reversal is +1.74%, paired
+895.42 ns, six of six slower. These smaller costs and mixed distributions are
limits on the result, not a blanket no-regression statement.

Neither rejected ASCII-normalization prototype is in this runtime patch. Their
distinct large ASCII benefits and repeated Unicode costs remain separate
evidence; this phase measures the word-only candidate.

## Rust reversal discovery

The new idiomatic optimized Rust reference reverses Unicode scalar order into
an owned String with `chars().rev().collect()`, including combining marks, NUL,
replacement characters and ZWJ. Setup is outside clocks; every measured complete
output is compared and consumed. Rust 1.99.1, optimization level 3, checked
arithmetic, frame pointers and opaque non-inline guards are recorded in
[the reference notes](rust-reverse/README.md). The 83 ordered input identities
and expected full outputs passed independent Python and executable checks.

| Case | Manuscript baseline ms | Rust ms | Manuscript/Rust |
| --- | ---: | ---: | ---: |
| ASCII 1 MiB | 3.342 | 1.223 | 2.73x |
| two-byte scalars, 65,536 copies | 1.616 | 0.422 | 3.83x |
| early-Unicode 1 MiB | 3.478 | 0.774 | 4.49x |

All six pairs favor Rust for these cases. The algorithms and allocation
strategies differ, despite equal observable scalar-reversal semantics. The Rust
process retains all prepared inputs; Manuscript prepares one case at a time.
Tiny observation overhead and setup/cache differences prevent a general language
ranking. These measurements identify a separate actionable investigation;
they are not a reversal fix and do not revive rejected PR #1969.

## Checks, artifacts and remaining work

The two byte source tests pass in Debug and Release against the final archive.
Five scoped native pure-search model tests, workspace/all-target Clippy with
warnings denied, Rust formatting and repository checks pass. Full workspace
execution/conformance remains excluded by this campaign's denied mechanism
scopes. Normal required remote checks stay enabled. Independent review verifies
all 7,310 rows, identities, paired summaries, actual input/program/compiler/
archive hashes and source-state patch. It finds no new blocking regression and
supports word-only publication with the disclosed small costs. No external
approval was submitted. Publication and the final merged-main campaign replay
remain separate gates.

The text-only package preserves all normal build/check logs, source-state and
input snapshots, metadata, protocols, inventories, summaries and raw samples.
Source snapshots use `.txt` suffixes with unchanged bytes; recorded original
paths remain provenance. No executable, native archive or helper IR is
published. `package-record.json` hashes the initially copied artifacts; the
parent manifest covers the completed package including this report.
