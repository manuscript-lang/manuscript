# Lexer, parser, and syntax efficiency pass

Measured on 2026-10-18. This pass changes allocation behavior without changing
grammar, diagnostics, original byte positions, parser recovery, or traversal.
It adds no runtime dependency on an external Go installation or Delve.

## Revisions and environment

- Production baseline: `9a2dc4e62858aa0d70cb5cf35848d6d34a32e449` (then-current main).
- Baseline with identical benchmarks/tests: `aa517f3671b9ce52c472155d79f93e07d8cad2b3`.
- Final production: `a9f7e38f16e80d696b63597cf91529c9ccebb6f1`.
- Lexer/syntax candidate binaries were built at `1375a8f7`; their production and
  benchmark sources are unchanged at the final production revision.
- Parser declaration/recovery samples were recorded at `045b226b`. Those workloads
  contain no text literals and their executed production paths are unchanged.
  All text, full plain-text Parse, and real-source samples use the final production
  decoder at `a9f7e38f`.
- Go 1.25.1 linux/amd64, Linux 6.18.55, AMD EPYC 9V74 virtual CPU; five visible CPUs,
  cgroup CPU quota four CPUs, 16 GiB memory limit. No CPU affinity or frequency control.
- Timings: `GOMAXPROCS=1`, default GC, no concurrent local tests/benchmarks; six
  samples per case/revision, 200 ms target per sample. Three rounds of two samples,
  ordered before/after, after/before, before/after. Baseline and candidate binaries
  were built before the matched runs. Inputs were prepared outside the timed loop.

`samples-before.txt`, `samples-after.txt`, and `summary.csv` retain every final
sample, medians, allocation counts, and timing ranges. Earlier exploratory samples
were excluded. Timings are process-local throughput measurements, not cold CLI or
editor latency, statistical significance claims, or native generated-code speedups.
B/op measures cumulative Go allocations, not peak RSS. The retained-heap experiment
below measures a separate lifetime cost after GC, also with `GOMAXPROCS=1`.

## Coverage and decisions

| Package | Inspected and exercised | Outcome |
| --- | --- | --- |
| `pkg/lexer` | Identifiers, numbers, strings/interpolation, punctuation, indentation/delimiters, malformed input, LF/CRLF/mixed positions and EOF | Reuse punctuation from constant storage; keep cumulative CRLF corrections per line instead of per byte. Pure LF still needs no table. |
| `pkg/parser` | Strict parsing, defaults, types, patterns, chains/nesting limits, text decoding, partial declaration/statement recovery and rebasing | Clone validated plain payload once; preserve the original escaped/interpolated decoder as a helper. Partial recovery still has a quadratic continuation workload. |
| `pkg/syntax` | AST/positions, Visitor/Nodes source-order traversal, nested-match advisory, diagnostic serialization and kind inventories | No production change justified: measured traversal is allocation-free and approximately linear. |

Existing conformance/grammar/nesting tests remain active. New position tests use
an LF token/diagnostic oracle mapped through original line starts, including UTF-8
byte columns, mixed/trailing endings, lone CR, malformed Unicode/unknown escapes,
raw newlines in text, and unterminated/mismatched delimiters. Text tests exercise
strict and partial parsing, empty/Unicode/escaped payloads and original positions.

## Selected results

Medians; exact samples and all cases are in the adjacent files.

| Workload | Before ns/op | After ns/op | Before B/op | After B/op | Before allocs/op | After allocs/op |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Lex 128 declarations LF | 752791 | 728387 | 3418047 | 3400639 | 4503 | 151 |
| Lex 128 declarations CRLF | 743509 | 762862 | 3650224 | 3424447 | 4522 | 153 |
| Lex 256 KiB comment CRLF | 911405 | 246763 | 3295888 | 274336 | 44 | 12 |
| Lex 256 KiB comment LF control | 212529 | 211922 | 3992 | 3968 | 16 | 10 |
| Decode plain text 64 KiB | 116307 | 5622 | 285744 | 65848 | 24 | 3 |
| Full Parse plain text 64 KiB | 220954 | 107869 | 290992 | 71072 | 52 | 25 |
| Decode late escape 64 KiB control | 117290 | 113254 | 285744 | 285744 | 24 | 24 |
| Decode late interpolation 64 KiB control | 134100 | 135402 | 288680 | 288656 | 45 | 39 |
| Parse collections.ms | 398704 | 367558 | 1054032 | 1046946 | 3396 | 1624 |
| Parse testing.ms | 100901 | 90337 | 274696 | 272696 | 995 | 495 |
| Parse pipe-flow.ms | 138936 | 125978 | 348352 | 345760 | 1330 | 818 |

The representative lexer allocation count falls about 97%, while byte savings
are smaller because token-slice storage dominates. Declaration time varies: the
128-declaration CRLF median is 2.6% slower, so no universal speedup is claimed.
Full Parse of 128 CRLF declarations is also 8.2% slower (1.739 to 1.881 ms),
with overlapping ranges of 1.687–1.837 and 1.776–1.932 ms. These declaration
workloads have no text literals and receive only the lexer changes.
Long-comment CRLF allocated bytes fall 91.7% and time falls 72.9%. Per-line mapping
particularly helps long lines; short-line files have smaller memory gains.

The final late-interpolation median is 1.0% slower, with overlapping ranges
(before 131480–136902 ns; after 134524–140183 ns). Small escaped/late-escape
64-byte controls are about 3–4% slower, with overlapping ranges. Larger escaped
controls do not show a consistent slowdown; allocations are unchanged. Full
plain-text parsing improves 51.2%; the actual-source cases improve 7.8–10.5%.
These local results do not predict every source distribution.

Visitor at 64/128/256 declarations is 16.4/34.6/78.0 us before and
16.9/35.0/78.1 us after, always zero allocations. Nodes is
22.3/46.0/99.1 us before and 22.5/45.7/97.9 us after, also zero allocations.

## Rejected alternatives and remaining scaling issue

- Source-backed punctuation slices would newly retain huge comment-only inputs.
  Slices of a fixed constant avoid both allocations and source retention.
- Retaining plain-text substrings was rejected. Keeping only 16 tiny import paths
  after parsing sources with 1 MiB comments retained 544 bytes on baseline,
  16908544 bytes with the raw-slice candidate, and 528 bytes with cloning. Three
  repeated process runs gave the same deltas. The punctuation control retained
  7808 bytes before and 7552 after. `tools/retained/main.go` reproduces the case;
  the raw-slice candidate is `1375a8f7`, baseline is `aa517f36`.
- An inline fast path using ContainsAny regressed a long late-escape case 32.4%.
  Replacing it with byte searches still regressed slow-path code generation in
  that function shape. This pass therefore puts the fast path in a small wrapper;
  its fallback decoder body is byte-for-byte identical to baseline. Compiler
  layout/code-generation effects are a hypothesis, not an established cause.
- Partial recovery re-lexes growing prefixes to identify column-zero delimiter
  continuations. At 64/128/256 parameters, baseline takes 1.02/3.63/14.11 ms and
  allocates 2.89/11.05/43.75 MB. With lexer allocation savings, the corresponding
  candidate is 0.88/3.06/12.52 ms and 2.85/10.92/43.21 MB. The quadratic behavior
  remains. A shared/incremental lexer boundary design needs a separate recovery
  contract review; this pass does not replace delimiter-aware recovery with
  textual delimiter counting or change omission/diagnostic behavior.

## Validation

At final production revision `a9f7e38f`:

- `go test -count=1` passed for syntax, lexer, parser, frontend, project, checker,
  compiler, lower, and tooling including docgen/guide/LSP.
- `go vet` passed for the same packages.
- `go test -race -count=1 ./pkg/lexer ./pkg/parser ./pkg/syntax` passed.
- Strict parser fuzzing: 268904 executions in 11 seconds; partial parser fuzzing:
  468430 executions in 10 seconds; both passed with two workers.
- `make repo-check`, read-only repository formatting check, and `git diff --check`
  passed. Go's VCS discovery fails in this sandbox worktree; these checks used
  `GOFLAGS=-buildvcs=false`, which changes build metadata only, and a writable
  GOCACHE/GOMODCACHE. No repository policy was skipped or changed.
- Complete serialized token/strict AST/partial AST/diagnostic output matched for
  298 tracked Manuscript files under original, CRLF and mixed endings (894 cases).
  SHA-256 of both aggregate result files:
  `932e158a792b3cf51e68695175f1cbf3ddec35e1f630b9fb4e924230e1adb2f1`.
- Native execution, full distribution and cross-platform tests are delegated to
  required PR CI; local checks do not establish those results.

## Reproduce

Use the repository-pinned SDK (`sh scripts/bootstrap-go.sh`) and writable cache
directories. Build baseline/candidate test binaries from the exact revisions,
then run each binary from its package directory. For example:

```sh
GOMAXPROCS=1 ../../path/to/parser.test -test.run '^$' -test.bench . \
    -test.benchmem -test.benchtime=200ms -test.count=2
```

Alternate revisions for three rounds as above. Run lexer and syntax binaries
similarly. Rebuild neither revision during timing. Keep the benchmark corpus
files identical; this pass used the three paths named by BenchmarkParseCorpus
from production baseline `9a2dc4e6`.

From the repository root, complete-output comparisons can be reproduced with:

```sh
git ls-files '*.ms' > /tmp/manuscript-performance-corpus.txt
toolchain/go/bin/go run ./pkg/parser/testdata/performance/tools/corpus \
    /tmp/manuscript-performance-corpus.txt > /tmp/corpus-results.txt
GOMAXPROCS=1 toolchain/go/bin/go run ./pkg/parser/testdata/performance/tools/retained path
GOMAXPROCS=1 toolchain/go/bin/go run ./pkg/parser/testdata/performance/tools/retained punctuation
```

Run the same tools against both revisions (copying the tools into the baseline
worktree or using Go source overlays) and compare outputs. The Go SDK is a
development measurement tool here; released Manuscript tooling remains self-contained.
