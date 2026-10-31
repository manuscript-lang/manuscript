# Rejected Float ASCII-scan optimization

Measured 2026-10-31 against main `83826bb7ecedb032a36c6b60719f04bbac135e2b`.
**Rejected: no production code or live tests change.** Skipping UTF-8 validation
after an ASCII grammar check improved valid Float parsing, but independently
confirmed invalid-input regressions make the tradeoff unsuitable. This follows
the [rejected integer-radix trials](../integer-parse-radix/README.md).

## Candidate and decision

[`variants/rejected.patch`](variants/rejected.patch) preserves the unapplied
candidate and its focused tests. `float_syntax` consumes the entire input and
accepts only ASCII, so successful validation proves the precondition for
`from_utf8_unchecked`. Replacing the subsequent checked conversion removes a
redundant scan without intentionally changing accepted text, rounding, range
errors, signed zero, or special values. Independent source review found no
correctness defect. That safety argument does not establish performance safety.

The final eight-phase session improved ordinary/scientific valid parsing about
18%, and wide valid parsing about 13%. Early invalid input slowed 10.6%, Unicode
rejection slowed 9.7%, and an unchanged long integer-error control slowed 5.3%.
Early-invalid and integer late-invalid regressions appeared in all eight pairs;
Unicode rejection slowed in six of eight pairs, against nearly flat A/A controls.
A predeclared longer confirmation retained the regressions:

| Confirmation workload | Paired after/before | A/A | Slower pairs |
| --- | ---: | ---: | ---: |
| Float early invalid | 1.102 | 1.001 | 16/16 |
| Float Unicode invalid | 1.092 | 0.996 | 16/16 |
| Int late-invalid decimal, 4,096 digits | 1.032 | 0.996 | 14/16 |
| Float ordinary valid | 0.814 | 1.003 | 0/16 |

All per-case times, Rust baselines, CPU ratios and paired counts are in
[`summary.md`](summary.md). No outliers or unfavorable cases were removed.
The unchanged-control regression's exact cause is unestablished; no backend,
disassembly, ownership, lifetime or parity investigation was performed.

One [predeclared build-location control](matched-plan.json) rebuilt both baseline
and the identical candidate sequentially in the same checkout, with the same
frozen compiler, source and flags. All four resulting benchmark executables were
**byte-identical** to the originals ([hashes](matched-result.json)). Build location
therefore does not explain these results. No additional timing, layout variants,
rebuild selection or attempted exoneration followed. The checked conversion was
restored, including rebuilding the default native archives and compiler.

## Equivalent workloads

[`main.ms`](main.ms) and [`rust.rs`](rust.rs) cover signed decimal formatting,
ordinary signed parsing, Float plain/scientific/wide/subnormal/signed-zero inputs,
4,096-zero underflow, exact special values, early/late malformed input, overflowing
short/long text, and Unicode rejection. The 33 existing radix/Float-format controls
use the unchanged exact sources from the [prior report](../integer-parse-radix/README.md):
`measured-main.ms.txt`, `rust.rs`, and `repeat.py`.

Both languages prepare identical inputs outside internal monotonic timers, consume
every result and check required checksum/final text before successful exit. Valid
Float parsing compares every result to the expected numeric value; signed zero is
also checked before timing. NaN is classified explicitly. Signed integer parsing
checks all 1,000 inputs exactly before timing; timed results use a residue checksum
and final exact text, which does not prove every intermediate value. Formatting
checks lengths and final text. Rust uses input/output `black_box` barriers.

Rust's `strict_float` matches Manuscript's complete syntax, exact special spellings
and rejection of numeric infinity, then calls idiomatic `str::parse`. Bare Rust
Float parsing accepts a different grammar, so it is not the comparison here.
Error performance checks use public `is_none()` in both languages; the saved source
tests additionally check exact `NumberError` identity. These are matched workload
results, not universal language or standard-library parity claims.

An unsigned-formatting output control failed before timing. That path was stopped
and referred for correctness handling; its output/cause were not established and
it is excluded from these producers and performance conclusions. No alternate
validation of that boundary was attempted.

## Measurement protocol

Linux 6.18.57 x86_64, AMD EPYC 9V45, four-core CPU quota (`400000 100000`),
16 GiB memory limit. Official Rust/Cargo 1.99.1, rustc
`58cf8f9c35b355199727627d07ae34a4e2846d67`. Native archives used
`cargo xtask runtime`; one frozen `cargo build --release --locked -p ms-cli`
compiler built both Manuscript copies with `--build-type Release` and `MS_RT_LIB`
selecting the archive. Default backend selection remained unchanged. Rust used:

```sh
rustc --edition=2024 -C opt-level=3 -C overflow-checks=on \
  -C force-frame-pointers=yes --target x86_64-unknown-linux-musl rust.rs -o final-rust
```

Every producer runs on the lowest available CPU. Builds/tests are excluded from
measurement sessions. Internal timing excludes setup, startup and printing;
whole-process CPU/wall controls include them. Shared-host scheduling remains
visible in the raw distribution. No allocator, RSS or instruction measurement is
claimed. The Float parsing helper allocates no buffers before or after this change.

Four labels are baseline, identical-byte baseline A/A, candidate, and equivalent
Rust. Each session checks counts 1/2/1,000 before one warmup and eight measured
phases. Case order rotates; producer positions rotate then reverse, balancing
all positions and pair orders. Ordinary conversion samples use 1,000,000 operations,
long Float cases 7,812; old controls use 300,000 or 4,687 for long cases. The
confirmation uses one warmup plus 16 balanced phases: 20 million operations for
short Float errors, 50,000 for the long integer control and two million for valid
Float parsing. It reuses already output-validated executables.

| Dataset | Successful producers | Tiny controls | Warmups | Measured |
| --- | ---: | ---: | ---: | ---: |
| [Final conversions](results/conversions.jsonl) | 768 | 192 | 64 | 512 |
| [Final existing controls](results/controls.jsonl) | 1,584 | 396 | 132 | 1,056 |
| [Long confirmation](results/confirmation.jsonl) | 272 | 0 | 16 | 256 |

All **2,624** invocations succeeded. Earlier exploratory sessions are retained
locally but do not establish the final decision; this report uses the complete
final sessions and the longer confirmation. [`artifacts.json`](artifacts.json)
records revision, compiler/archive/executable hashes and retained source/data hashes.
Historical absolute paths in raw records and the matched-location plan identify
measured artifacts; portable runners accept new executable paths.

## Correctness, review and remaining coverage

Three focused native tests passed for the final candidate, including exhaustive
insertion/replacement of every non-ASCII byte in nine numeric/special-form seeds (14,720
mutations) plus six Unicode lookalikes. The syntax assertion runs before conversion.
The [two saved public source tests](source-tests.ms) passed in Debug and Release,
covering ASCII signs/exponents/signed zero, Unicode/malformed rejection, exact range
errors and 4,096-digit overflow/late invalid text. The four existing public
`string-parse-float` tests also passed in Debug and Release. Scoped runtime Clippy
with warnings denied and Rust formatting passed. These tests are preserved as
evidence inside the unapplied patch and source snapshot, not added to live fixtures.

Independent read-only review checked the ASCII safety proof, public behavior,
benchmark equivalence, negative controls and evidence. The evidence-only tree is
also audited for hashes, counts, ordering, outputs, summaries, patch applicability
and production restoration. Broad workspace execution and excluded backend,
ownership/lifetime, Windows, network and Float32 paths are not a clean pass.
Unsigned output correctness remains blocked. A final replay after all campaign
merges is still required; these measurements do not establish that checkpoint.
The known valid integer parsing gap remains unresolved; no optimization survives
this lane's invalid-input controls.

## Subsequent current-main checkpoint

After rejecting the candidate, normal archives and the compiler were built at
main `26d586480a0aa786035d3def7bfe47651c96e297`. All 49 cases were replayed against
the clean pinned baseline with equivalent Rust and A/A, using the same eight-phase
protocol. The numeric helper/declaration blobs were unchanged from the baseline.
Independent review verified all **2,352** additional successful producers (588 tiny
controls, 196 warmups, 1,568 measurements), outputs, counts, ordering, timings,
summaries and executable hashes. Raw data are retained as
[checkpoint conversions](results/checkpoint-conversions.jsonl) and
[checkpoint controls](results/checkpoint-controls.jsonl); full tables follow the
rejected trial in `summary.md`.

Paired current/baseline medians ranged **0.978–1.030**. The largest increase had
A/A 1.019 and current/A/A 1.017; these samples do not establish a material new
regression. The rejected candidate's short Float-error regressions are absent
(early 1.009, Unicode 1.010). Existing short valid Float parsing remains about
1.13–1.27× Rust and generic valid radix parsing 1.54–2.17× Rust for these workloads.
Those gaps are unresolved; further speculative variants were not pursued. This
is a dated main checkpoint, not the still-pending final all-campaign replay or a
clean result for blocked/excluded paths.

## Audit and replay

From this directory, audit the retained data without executing benchmark binaries:

```sh
python3 validate.py > /tmp/float-parse-summary.md
diff -u summary.md /tmp/float-parse-summary.md
```

For a new experiment use separate worktrees at the pinned baseline, apply exactly
one saved patch, build both native archives, then build both copies of `main.ms`
with the same frozen compiler. Build the existing control producers from their
exact sources as well. Preserve the historical results rather than overwriting
them. Ordinary replay uses:

```sh
python3 repeat.py ./final-before ./final-aa ./final-after ./final-rust \
  --repeats 8 --count 1000000 > new-conversions.jsonl
python3 ../integer-parse-radix/repeat.py ./final-controls-before ./final-controls-aa \
  ./final-controls-after ./integer-rust --repeats 8 --count 300000 > new-controls.jsonl
python3 confirm.py /absolute/directory/containing/final-executables \
  /absolute/path/integer-rust > new-confirmation.jsonl
```
