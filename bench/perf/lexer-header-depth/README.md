# Held lexer header-depth experiment — 2026-10-31

**Held, not accepted for production.** The tail check preserves semantics and
consistently speeds deep inputs, but a fresh-main run showed an unexplained
11% tiny-parse regression in all ten pairs. A later favorable run cannot erase
that observation. The candidate remains on an unmerged experiment branch;
the evidence-only PR does not change the production lexer.

## Complete decision record

| Run | Samples | Tiny parse, baseline → candidate | Deep LF512 lex speedup |
| --- | ---: | --- | ---: |
| Initial baseline56ea comparison | 1000 | 0.432 → 0.423 µs | 2.57x |
| Fresh-main e01fb141e, separate build paths | 1000 | 0.432 → 0.480 µs | 2.55x |
| Identical-baseline A/A path control | 160 | 0.434 → 0.431 µs | not measured |
| Same-path build, regenerated input identities | 1000 | 0.434 → 0.434 µs | 2.52x |

The A/A control does **not** establish a build-path cause. The candidate binary
in the bad and later flat runs has the identical SHA-256
`3dbb685921cbd9245792be7063d2edf5796b627a66319862724e9f280fc57ff0`.
Source bytes are also identical, but full input filename identities differ
between output directories. Their relevance is unproven. Do not call the bad
run noise, attribute it to code placement, or choose a favorable input identity.

All four runs, the same-path build commands/fingerprints and both rejected
reservation alternatives are preserved. `tail-check.patch` is a counterfactual
only. Independent review confirmed the source invariant, all sample/order/
checksum checks, and the final decision to hold publication. No GitHub approval
was submitted.

Any future attribution protocol must predeclare and hold actual input and
invocation identities fixed, include the original problematic identity, and
retain every result. The historical runner regenerates fixture paths beneath
each output directory; it is retained for reproducing these observations, not
as a completed attribution method. No further layout, flag or path tuning was
performed to produce a green result.

The historical initial-run report follows; its favorable results alone are
insufficient to accept the production patch.

The lexer records delimiter depths for `fn` and `match` headers. Each push uses
the current depth, and closing a delimiter pops greater depths. At every query
the vector is nondecreasing and no entry exceeds the current depth, so membership
at that depth is equivalent to checking the tail.

Scanning the whole vector on every physical line makes deep multiline function
types quadratic. Checking the tail removes that rescan without changing tokens,
layout, AST metadata, diagnostics or any buffer-reservation policy.

Baseline: `56eaef0a97d356ad6253ed43ac0e4aeaad991735`.
Candidate source: `0848ab2602f4e42cec5a33f75e38914877326c7a`.
Source/binary/input hashes and the original dirty-checkout HEAD are retained in
`results-2026-10-31-initial.json.gz`; the source commit identifies the exact
measured lexer. These measure the **Rust compiler implementation**, not generated
Manuscript programs against Rust programs. No checker, lowering or runtime path
is executed.

Linux x86_64, kernel 6.18.57, glibc 2.41, AMD EPYC 9V45 VM, CPU 0. Rust 1.99.1;
release opt-level 3, debug 1, panic abort, frame pointers enabled.

| Input | Mode | Baseline µs/pass | Candidate µs/pass | Speedup |
| --- | --- | ---: | ---: | ---: |
| Function depth 64, LF | lex | 3.337 | 2.894 | 1.15x |
| Function depth 128, LF | lex | 6.710 | 5.185 | 1.29x |
| Function depth 256, LF | lex | 15.675 | 9.750 | 1.61x |
| Function depth 512, LF | lex | 47.878 | 18.621 | 2.57x |
| Function depth 512, CRLF | lex | 59.347 | 30.461 | 1.95x |
| Function depth 512, LF | parse | 130.828 | 101.388 | 1.29x |
| Function depth 512, CRLF | parse | 142.469 | 113.131 | 1.26x |
| Tiny source | lex | 0.144 | 0.144 | 1.00x |
| Dense 256-element source | lex | 2.175 | 2.188 | 0.99x |
| Dense 32768-element source | parse | 2107.493 | 2113.776 | 1.00x |
| 4096 declarations | parse | 2195.169 | 2200.392 | 1.00x |
| One MiB comment | parse | 606.488 | 617.605 | 0.98x |
| Standard-library corpus | lex | 1540.780 | 1482.020 | 1.04x |
| Standard-library corpus | parse | 4869.631 | 4773.145 | 1.02x |

The large-comment parse control moved about 1.8% with a broad paired range that
crosses parity. Preserve that observation; it is not a demonstrated allocation
or comment-scanning improvement. Common controls remain approximately unchanged.
Do not generalize these measurements to universal compiler or language parity.

## Protocol and correctness

There are 25 input groups in lex and parse modes, ten balanced AB/BA fresh-process
pairs each: 1,000 raw samples. Order is shuffled with seed 1729; each process
warms three passes and times at least 100 ms in batches of 16. Every result is
black-boxed, counted and checked. Parsing includes source retention and
destruction; lexing includes normalization, scanning and destruction. Setup,
I/O, exact-output validation and process startup are outside the timer.

Before timing, complete normalized-source/token streams and strict syntax
trees/dumps match, including IDs and positions. Inputs include tiny and ordinary
sources, LF/CRLF, long comments/text, dense lists, long bodies, many declarations,
deep function types, and `fn`/`match` suites inside open delimiters. The corpus
contains 45 standard-library files. Raw distributions and paired order statistics
are retained; no CI timing threshold was added.

`multiline_function_types_keep_only_the_enclosing_function_suite` verifies
depths 1 through 512 with LF/CRLF, one enclosing suite, the full function-type
tree, and original positions. `delimited_function_and_match_suites_keep_their_boundaries`
verifies both header kinds inside open delimiters, later grouping boundaries,
and formatting idempotence. Full syntax tests, focused clippy, formatting and
repository checks pass. An independent reviewer verified the ordering invariant
across every stack mutation. These correctness checks do not resolve the observed
shallow performance cost; the production optimization remains held.

## Reproduce

Build each pinned checkout with `cargo build --release --locked -p ms-syntax`.
Compile the same saved [shared harness](../parser-suffix/bench.rs) against each
release library using the [existing flags](../parser-suffix/README.md#reproduce).
The measured harness source is from `11d6d8696c875a3ad225f6d4d4deb9d0ceed01ac`;
copy it outside both checkouts before changing revisions. Also compile
`tokens.rs` against each library (Rust 2024, `-O -D warnings -C panic=abort`).
Use a new output directory outside the checkout:

```sh
python3 bench/perf/lexer-header-depth/run.py \
  /tmp/base-bench /tmp/candidate-bench /tmp/base-tokens /tmp/candidate-tokens \
  /tmp/header-results \
  --baseline-revision 56eaef0a97d356ad6253ed43ac0e4aeaad991735
```

Run without concurrent builds or benchmarks. The runner pins itself and children
to the first available Linux CPU; host isolation is not claimed. Compressed JSON
uses ordinary gzip and preserves every sample. Allocation counters and RSS were
not measured for this tail-check change; its data structures and reservations
are unchanged.

## Rejected allocation alternatives

A separate pass found that a one-MiB comment reserves 9,437,760 bytes of token
capacity for one EOF token. Deleting the reserve or retaining its existing
minimum of 16 cuts that capacity to 144/576 bytes. Both alternatives were
rejected: deletion slows tiny parsing about 21%; fixed 16 slows small dense
lexing about 10% and corpus parsing about 2%, consistently across paired trials.
Dense large token capacity nearly doubles. Capacity is not measured RSS.

All 468 samples from that three-way experiment are preserved in
`rejected-reservation-results.json.gz` with both patches. The six producer-order
permutations were balanced across 13 cases and both modes; exact lexer outputs
match. An independent reviewer confirmed rejection. These patches are evidence
only: the production reserve remains exactly as before. The allocation
opportunity remains unresolved; do not report this whole lane universally clean.
