# Partial-parser continuation recovery measurements

This follow-up targets repeated prefix lexing in `ParsePartial` after a strict
parse has failed elsewhere. A valid function with 64, 128, or 256 column-zero
parameters was repeatedly lexed up to every parameter. This made recovery of
that valid root quadratic. Strict parsing, grammar, synchronization rules,
diagnostics, spans, and statement repair remain unchanged.

## Revisions and method

- Baseline: `95ec85602c3d08a8de6d96de45df89e80bbd2d2a`.
- Measured candidate: `42f92e8a3269b41b74c4ad3d8cc5cdaef7432990`.
- Both binaries contain the identical benchmark/oracle test files whose SHA-256
  hashes appear in `measurement-environment.json`. The baseline has only those
  two test files overlaid; its production code is unchanged.
- The candidate was subsequently rebased onto `12ef3b75`; that main advance
  changes no files in `pkg/syntax`, `pkg/lexer`, or `pkg/parser`.
- Pinned Go 1.25.1, linux/amd64, AMD EPYC 9V74 virtual CPU, Linux 6.18.55,
  `GOMAXPROCS=1`. The container exposes five CPUs, has a four-CPU quota and a
  16 GiB memory limit. These are local container measurements, not CI timings.
- Six 200 ms samples per benchmark per binary, alternating before/after order
  between pairs. No fuzzing, builds, tests, or reviewer runtime work ran during
  this measurement series. Input generation and oracle checks precede `b.Loop`.
- `GOFLAGS=-buildvcs=false` avoids the workspace's synthetic parent Git metadata
  during builds; it changes build metadata only. No policy or test is disabled.

`samples-before.txt` and `samples-after.txt` retain all 576 benchmark samples
(trailing spaces in Go CPU header lines removed).
`summary.csv` contains medians and full observed timing ranges for all 48 cases.
Percentages below compare medians; no statistical-significance claim is made.

## Results

| Workload | Before | After | Time change | Bytes/op before → after |
| --- | ---: | ---: | ---: | ---: |
| Valid continued function, 64 parameters | 935.1 µs | 71.6 µs | −92.3% | 2,853,531 → 156,462 |
| Valid continued function, 128 parameters | 3.327 ms | 131.8 µs | −96.0% | 10,915,834 → 308,797 |
| Valid continued function, 256 parameters | 12.444 ms | 278.6 µs | −97.8% | 43,211,926 → 875,892 |
| Same 256 parameters, CRLF | 13.683 ms | 297.8 µs | −97.8% | 44,012,949 → 888,757 |
| First-root grouped import, 256 names | 6.432 ms | 144.8 µs | −97.7% | 21,379,437 → 371,123 |
| First-root constant list, 256 elements | 6.269 ms | 150.8 µs | −97.6% | 21,492,189 → 353,818 |
| 256 separate continued functions | 2.711 ms | 2.290 ms | −15.5% | 4,134,734 → 3,617,607 |
| Unterminated function, 256 parameters | 12.041 ms | 12.111 ms | +0.6% | 42,747,675 → 42,747,661 |
| Invalid statement after 256 parameters | 12.376 ms | 12.394 ms | +0.1% | 43,696,211 → 43,696,601 |
| 256 short unfinished functions | 2.333 ms | 2.356 ms | +1.0% | 1,668,423 → 1,668,422 |
| 256 short closed but invalid signatures | 2.105 ms | 2.043 ms | −3.0% | 3,573,796 → 3,620,405 |
| 256 unsupported call chunks | 49.775 ms | 48.791 ms | −2.0% | 162,047,747 → 162,048,111 |
| Ordinary recovery, 128 declarations | 498.3 µs | 499.0 µs | +0.1% | 1,297,100 → 1,297,100 |
| Ordinary strict success, 256 declarations | 500.6 µs | 516.7 µs | +3.2% | 1,591,748 → 1,591,748 |

The valid-header time doublings change from 3.56×/3.74× to 1.84×/2.11×.
Valid-header allocations at 256 parameters fall from 4,985 to 606. The remaining
allocation jumps include the lexer's existing token-slice growth. Unterminated
headers still grow roughly quadratically: 0.876/3.127/12.041 ms before and
0.911/3.152/12.111 ms after at 64/128/256 parameters. Unsupported module calls
behind an unmatched opener also retain the old quadratic path.

Controls are not uniformly faster. The short 64-parameter unterminated control
has a +4.1% median (observed ranges overlap). Strict success at 256 declarations
has a +3.2% median with overlapping ranges: 486.5–537.1 µs before and
487.2–550.5 µs after. Its execution returns before the new recovery machinery,
and its bytes/allocations are unchanged. The tiny invalid-signature cache adds
about 46.6 KB per 256 roots (+1.3% bytes, about 17 allocations) while eliminating
the duplicate strict parse. These limits are retained in the raw data.

## Bounds and behavior

After the original lexer reports an unterminated prefix, attempt at most one
strict parse for that original start. Only possible module-root starts qualify;
lookahead ends before the next such start, including `let`, `import{`, and
`let(`. This bounds added scanning/probing by disjoint source intervals, including
unsupported module-level calls. The root filter never sets a recovery boundary.

A successful parse containing exactly one written root permits skipping its
interior prefix probes. Grouped imports/constants count as one written root.
Under the current grammar, suites require indentation, strings fit on one line,
and a valid root cannot continue at column zero past an unsuppressed newline
without an open delimiter. The candidate-end line still goes through the
original splitter. Exact final start/end matching gates reuse of either a
successful parse or a failed parse's diagnostic; failed probes never skip lines.

The first chunk still begins at byte zero, including leading comments. Chunks
are not coalesced: doing so would alter recovered spans and could cause a small
name to retain another root's large CRLF-normalized buffer. A closer-presence
check rejects guaranteed-failing unfinished probes; it neither balances
delimiters nor treats comments/text as code. False positives use the normal
strict parser and original fallback.

Temporary cache storage is linear in attempted roots/source size. Failed
diagnostics can retain token/source storage through their position pointers;
they are not necessarily constant-size payloads. Returned AST storage still
uses the same original chunks. No cache survives the call or is shared between
callers.

## Validation and memory

- `TestPartialContinuationDifferential`: 3,468 combinations of declaration,
  import, binding-group, trivia, unsupported-call and malformed fragments with
  LF/CRLF/mixed endings, plus generated 32-line positive/negative workloads.
  `legacyParsePartial` is the immutable baseline splitter, including its errors.
- `TestPartialContinuationLeadingTriviaAndRecoverySpan`: mixed-ending leading
  comments with both cached success and repaired fallback; the first repaired
  range must start at zero and end at the original next declaration.
- A separate before/after executable comparison hashes complete tokens, strict
  results/errors and partial trees/diagnostics for 320 tracked `.ms` files ×
  five damage variants × three ending variants: all 4,800 hashes match. Damage
  variants include unmatched prefix/suffix, leading trivia, and half truncation.
- Differential fuzzing after the final production change: 20 seconds, 631,663
  executions, no mismatch. Existing parser and recovery regression tests pass.
- Broad unit checks for syntax, lexer, parser, frontend, project, stdlib,
  checker, runtime, tooling (including LSP/guide/docgen), and repo-check pass.
  Focused race tests, focused `go vet`, and repository formatting checks pass.
- `retained.txt`: six fresh process pairs retain just 16 small declaration names
  from CRLF partial trees with 16 later 1 MiB comments. Both versions retain
  38,720–38,736 bytes after GC, so the later buffers are not pinned.
- `memory.txt`: single-call allocation counters corroborate the steady-state
  benchmark savings (valid 256: 43,212,128 → 913,416 allocated bytes). Fresh
  process counters include initial diagnostic pools, unlike warmed benchmarks.
  End-of-call heap-in-use is GC-phase dependent and is not peak heap. OS RSS
  readings all hit the launcher's 9 MiB floor, so they cannot establish a peak
  RSS change; no such improvement is claimed.

The discarded first prototype reparsed failed short headers, adding about 35%
bytes for unfinished headers and 36% for closed invalid signatures. The necessary
closer check and exact-bound failure reuse remove that duplicate work. Incremental
lexing/parsing might address all malformed continuations, but would require a
larger layout/recovery design outside this behavior-preserving change. Doing
nothing leaves the measured valid-root quadratic path in editor analysis.

## Reproduction

Use the repository's pinned SDK. Compile two test binaries, overlaying
`partial_continuation_test.go` and `partial_reference_test.go` on the baseline.
The candidate includes those files. Set writable caches for sandbox worktrees.

```sh
GOFLAGS=-buildvcs=false go test -c -o parser.test ./pkg/parser
GOMAXPROCS=1 ./parser.test -test.run '^$' -test.bench '^(BenchmarkPartialContinuation|BenchmarkParsePartial)$' -test.benchmem -test.benchtime=200ms -test.count=1
go test ./pkg/parser -run 'TestPartial' -count=1
go test ./pkg/parser -run '^$' -fuzz '^FuzzPartialContinuationDifferential$' -fuzztime=20s
git ls-files '*.ms' > corpus-manifest.txt
go run ./pkg/parser/testdata/performance/recovery/tools/corpus corpus-manifest.txt
GOMAXPROCS=1 go run ./pkg/parser/testdata/performance/recovery/tools/retained
GOMAXPROCS=1 go run ./pkg/parser/testdata/performance/recovery/tools/memory valid 256
```

Repeat the single-sample binary command six times, alternating binary order
between pairs. Compile the same supplied corpus/retained/memory tool source
against each revision and run against the same candidate manifest/checkout.
These are developer-only tools with standard-library imports; shipped runtime
and distribution requirements are unchanged.

## Owned-package coverage

| Package | Coverage and outcome |
| --- | --- |
| `pkg/syntax` | [Initial pass](../README.md) covers AST traversal/scaling; zero-allocation traversal had no warranted production change. Unchanged here. |
| `pkg/lexer` | Initial pass landed punctuation and CRLF mapping improvements in `55228347`; normalization ownership, malformed inputs and positions covered again by recovery differentials. Unchanged here. |
| `pkg/parser` | Initial pass landed plain-text decoding improvements in `55228347`. This follow-up improves valid continuation recovery, preserves malformed recovery, and explicitly retains its unresolved quadratic limit. |

Independent skeptical review used `gpt-6.1-sol` before implementation and on the
exact production revision; the frozen oracle and corpus comparison were also
independently checked. Publication remains gated on final-head review and CI.
