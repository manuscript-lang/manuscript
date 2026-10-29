# Public last-index search controls (unmeasured)

Prepared on `db975ce2f01ddf8da108ec9045ecaf66a63ab22c` in isolated branch
`perf/string-rfind`. This is an **unvalidated source hypothesis**, with no runtime
patch, native build, test execution or timing result. It is separate from rejected
split-searcher caching. No speedup or regression is claimed.

The public API was confirmed using `/tmp/string-round2/ms search_symbol` from a
small `/tmp` directory:

- `String.last_index_of(value: String) Optional[Int]` returns the last matching
  Unicode scalar index; the empty needle matches at `scalar_length()`.
- `Optional.get(default)` permits `.get(-1)` to represent absence here, because
  successful indexes cannot be negative.
- `clock().now()` supplies monotonic readings for elapsed time.

Root’s duplicate check found that #1034 already recorded a general reverse-end-hit
regression and explicitly deferred tiny fast paths. This proposal is a new
one-byte specialization for that known tradeoff, **not a newly discovered general
slowdown**. The historical broad substring benchmark is not being rerun.

The source hypothesis is narrow: local `rfind` sends all nonempty needles to
memchr 2.8.3 `memmem::rfind`; that dependency's public wrapper chooses Rabin–Karp
for haystacks below 64 bytes, even for one-byte needles. Direct one-byte search
could remove hash work. Longer haystacks already reach a one-byte `memrchr`
strategy. Tiny/near-end cases could instead lose to search setup, so this suite
retains them. Root independently evaluates any runtime candidate and controls
all native builds and timings. No quote/compiler reachability investigation is
part of this work.

## Fixed inventory and independent expected values

`generate.py` writes `main.ms`, `identities.json` and `oracle.json` and does not
build or execute Manuscript. Literal placement and scalar-count formulas supply
every expected index; Python's independent Unicode `str.rfind` checks those
formulas during generation. No measured Manuscript operation constructs an
expected result. The oracle records construction expressions rather than large
expanded input buffers.

The 101 cases contain:

- 55 one-byte cases, including five repeated near-end controls, with start, end,
  interior and miss placements where distinct.
- 14 empty-needle controls, including empty input.
- Seven two-byte and ten longer-needle fallback controls: longer-than-haystack,
  miss, overlap, boundary and scaling cases, including three bounded 4 KiB
  repetitive/overlap controls preserving the prior complexity repair. The tiny
  `"ac"` / `"ab"` miss has equal nonzero lengths and reaches the non-byte branch.
- Ten Unicode controls with ASCII and multi-byte needles, combining marks,
  multi-scalar needles, empty needles and non-byte scalar indexes.
- Five NUL controls: one-byte, start/end, repeated last hit and haystack-only NUL.

ASCII lengths are exactly 0, 1, 2, 7, 15, 16, 31, 32, 63, 64, 65, 128, 4096 and
1048576. The 63/64/65 controls straddle dependency dispatch. Unicode includes
`é`, `日`, four-byte emoji and a combining mark, plus a 36,865-byte scalar-index
conversion control. Public `last_index_of` includes prefix scalar counting after
a successful byte search; its cost must remain part of the reported operation.
Miss and beginning-hit controls separate that work. This suite does not measure
invalid internal UTF-8, constructors, allocation machinery or backend behavior.

## Timed operation and guards

Every operation calls `text.last_index_of(needle).get(-1)`, compares the actual
index with the fixed expected index, and consumes `actual + 19`. A mismatch
contributes −1; expected contributions are at least 18, so any mismatch makes the
final checksum fail. A checked warm-up precedes timing. Source construction,
expected-value setup, checked warm-up, compilation, process startup and printing
are outside the interval. Search, scalar-index conversion, Optional extraction,
exact result checking and checked checksum arithmetic are inside. These are
public end-to-end operation costs, not isolated native search costs.

Intervals use one million iterations through 128 bytes, 100,000 for intermediate
inputs, 65,536 from 4 KiB, 4096 from 16 KiB and 256 at/above 256 KiB. Iterations are fixed by input
byte count in both producer and identity manifest. Root may prepare longer
focused controls if measured intervals or common regressions require them; preserve
original trials and distinguish separately focused processes.

The shared strict runner verifies successful producer exit, exact headers,
complete identities exactly once, positive elapsed times, declared byte lengths,
iterations and checksums before a summary. Missing/duplicate/unknown rows or any
changed result reject the comparison. `identities.json` requires all 101 cases.
No CI timing threshold is added.

## Preparation and future commands

The generator ran successfully with all 101 Python scalar-index checks. The
Manuscript source is **not yet formatted, frontend-checked, built or run**. Those
steps, matched runtime archives and measurement require root's coordinated window.
No fixture or production source was changed by this preparation.

Example commands for root after pinning both archives and one compiler:

```sh
. /tmp/string-env.sh
MS_RT_LIB=/tmp/string-rfind-before/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /path/to/pinned/ms build bench/perf/string-rfind/main.ms --build-type Release -o /tmp/string-rfind-before/program --json
MS_RT_LIB=/tmp/string-rfind-after/libms_native.a MS_LLVM_TOOLS=/workspace/.cache/ms/llvm/d19868df5ca10629 /path/to/pinned/ms build bench/perf/string-rfind/main.ms --build-type Release -o /tmp/string-rfind-after/program --json
taskset -c 0 python3 /workspace/manuscript-strings-integrated/bench/perf/string-lines/compare.py /tmp/string-rfind-before/program /tmp/string-rfind-after/program /tmp/string-rfind-samples.csv --pairs 7 --identity-file bench/perf/string-rfind/identities.json
```

The shared runner path is the existing independently reviewed `--identity-file`
extension in the integration checkout; this preparation does not modify it. Save
raw samples, all medians/ranges and paired signs, exact source/compiler/archive/
helper/program hashes and normal public CLI/companion metadata. Report actual
metadata labels without inferring effective optimization or investigating code
generation. Do not run measurements during another coordinated build/test/timing
job. A measured result, independent review and normal gates are still required
before retaining any candidate.
