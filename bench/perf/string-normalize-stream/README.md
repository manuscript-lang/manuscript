# Lazy input decoding for Unicode normalization

Prepared candidate at baseline `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`.
Matched native builds and focused correctness checks pass. The initial 84-case comparison is recorded below; its prepared focused subset
has not been built or run.

The existing normalization path eagerly decodes the entire input into a
`Vec<char>` and then iterates that vector. The candidate supplies the same
`char::from_u32(utf8::decode(...))` sequence through `core::iter::from_fn`, removing
the intermediate input character buffer. Form validation, negative-budget
validation, UnicodeNormalization, UTF-8 encoding, output byte-budget checks,
status codes, and `from_buf` construction are unchanged. No ASCII scan or public
iterator API is introduced.

This does not promise bounded prefix decoding. The normalizer may look ahead
through a complete combining segment before yielding output, including when an
output budget will fail. Combining-segment controls retain that behavior.

The source fixture covers all four forms, typed and spelling-based dispatch,
composition/decomposition, compatibility, canonical reordering, Hangul, literal
U+FFFD/NUL, exact/exceeded/zero/negative byte budgets, invalid spellings, and a
long combining segment. Rust cases additionally use exact output bytes for
malformed, truncated, overlong, surrogate, and out-of-range sequences, preserving
one U+FFFD per invalid decoded byte rather than a lossy decoder's grouping.

The 84-case generated program uses independent literal output patterns. It
includes empty/one-byte ASCII and controls, every form, scaling patterns, a
complete combining segment, and successful/error budget controls. Expected
output construction and checked warm-up are outside timing. Timed operations
include normalization, complete output/status validation, and result release.
Every result contributes a checked checksum; `identities.json` fixes the entire
case inventory. No expected value is produced by the operation being measured.

Use the coordinated shared runner with `--identity-file` only after a native
build/correctness window and a separate timing grant. Baseline and candidate
runtimes must be built from the same source path, with an exit trap restoring
the candidate. Pin compiler/archive/helper/program/source hashes and preserve
normal public build metadata verbatim. Report its backend label without
inferring an effective optimization level or investigating code generation.

No acceptance decision is made by this implementation. Retain common-case and
error-path controls, and stop for a material reproducible regression. No
constructor, allocator, ownership, cleanup, compiler, or backend internals are
part of this candidate.

## Matched build and correctness evidence

Both runtimes were built from this same worktree path, temporarily restoring the
pinned baseline source with an exit trap protecting the saved candidate. Archives,
pure helpers, and source snapshots are pinned in
`/tmp/string-round2/normalize-before` and `/tmp/string-round2/normalize-after`.
The helper files are byte-identical. The untracked `target` symlink shares only
the coordinated build cache and is not part of this change.

All 22 Rust string tests passed, including the two new normalization cases.
All three new source tests passed in explicit Release and Debug profiles. The
existing two typed-normalization tests also passed in both profiles. These are
focused correctness checks; no workspace-wide or corpus result is claimed.

Both generated-program builds used the same pinned compiler and explicit cached
LLVM-tool path. Their normal companion metadata reports **Cranelift, Release**.
Effective optimization beyond that metadata is unverified; no backend inspection
or fallback investigation was performed. The public build JSON and companion
metadata are preserved verbatim; companion copies use ordinary names under
`build-metadata/`. `builds.json` records their hashes alongside
source, patch, compiler, archive, helper, program, fixture, and correctness logs.

## Initial v0 comparison, retained separately

The full 84-case comparison completed seven alternating pairs with all producer
and identity guards passing. `samples.csv` preserves all 1176 rows, `summary.csv`
every median/range, `paired.csv` paired signs and distributions, and
`paired-samples.csv` each pair's normalized times and deltas. These timings
include complete output or domain-error validation and result release.

Eleven ratio-of-median regressions remain below. Paired delta is the median
candidate-minus-baseline difference; signs and deltas are retained separately
from the ratio of medians. No noisy observation is discarded.

| Case | Before median ns | After median ns | Ratio | Paired delta ns | Slower pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `empty_NFC_full` | 24.7 | 25.5 | 0.968x | 1.310 | 5/7 |
| `empty_NFD_full` | 18.9 | 19.4 | 0.972x | 1.555 | 5/7 |
| `canonical_scale_65536_NFD_full` | 3326261.8 | 3452767.1 | 0.963x | 45772.375 | 4/7 |
| `canonical_scale_65536_NFKC_full` | 3658497.6 | 3673668.4 | 0.996x | -392952.000 | 2/7 |
| `compatibility_scale_4096_NFKD_full` | 294456.4 | 295329.8 | 0.997x | -4808.410 | 3/7 |
| `combining_segment_NFKD_full` | 15503.8 | 16676.8 | 0.930x | 2535.031 | 4/7 |
| `negative_NFC` | 5.1 | 5.1 | 0.994x | -0.283 | 3/7 |
| `negative_NFD` | 5.5 | 7.4 | 0.745x | 1.125 | 4/7 |
| `negative_NFKC` | 5.4 | 5.5 | 0.978x | -0.232 | 3/7 |
| `negative_NFKD` | 5.3 | 6.8 | 0.777x | 1.242 | 5/7 |
| `invalid_nul` | 6.8 | 7.0 | 0.978x | 0.613 | 4/7 |

Empty NFC/NFD and negative-budget costs need common-path assessment; canonical
NFD and combining-segment NFKD also had unfavorable medians. Other nominal
regressions have favorable paired signs/deltas. The 24-case `focused-controls.ms`
and `focused-identities.json` are prepared but unbuilt and unrun; no focused
result is implied.

A separate v1 in `../string-normalize-ascii` adds the genuinely new causal skip
of the whole Unicode identity algorithm for ASCII. Its 100-case matrix retains
every original control plus early/late Unicode-prefix controls. It does not
replace these v0 observations or establish that these regressions are resolved.
The initial v0 runtime source, archive, helpers, programs, and raw-data snapshots
remain pinned, including `/tmp/string-round2/normalize-v0`. V0 is not an
acceptance decision or a universal-speed claim.
