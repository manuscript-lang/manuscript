# Binding facts across repeated compiler checks — 2026-11-05

Issue [#2600](https://github.com/manuscript-lang/manuscript/issues/2600) is an
allocation defect: each new `Program` builds a zero-based flag vector through
its largest session binding ID, including IDs belonging to discarded analyses.
The candidate stores one byte per represented binding in a `HashMap`. Session
IDs, simultaneously live programs, cached/lazy standard declarations and the
six flag meanings are unchanged. This does not fix the separate session
subgraph-retention investigation in #2606, and makes no diagnostic-policy change
for #2609.

Baseline: `5ade79d71081246b35f9235595915b825336d6c0`. The measured candidate changes
only the production `BindingFlags` representation and its accessors;
`facts.rs` blob is `813ab6040e2fc1bd97a6e79b2ad166db1f942151`. The other production
change is a matching field comment. Tests and benchmark files do not participate
in the production checker build.

## Result and cost

Storage now follows the number of bindings with facts, independently of their
UID magnitude or gaps. The permanent regression retains an earlier program,
loads and reuses deferred CSV declarations, then checks the same source forty
times. It verifies stable, distinct identities and unchanged earlier facts,
while bounding later table capacity relative to the first table. Three tests
fail on the baseline: historical capacity growth, widely separated IDs, and
`usize::MAX` overflow. All 64 flag combinations and exclusive-borrow precedence
are also tested.

This is a bounded-memory correction, not a checker speed improvement. Seven
shuffled fresh-process trials per case give the following medians of each
process's median check time. Warm cases omit that process's first check; cold
cases make a fresh library session for each check.

| Fixed source/control | Vector ms | Map ms | Change |
| --- | ---: | ---: | ---: |
| cold, one alias | 40.183 | 41.101 | +2.28% |
| cold, 128 aliases | 42.520 | 43.521 | +2.35% |
| repeated, 128 aliases | 18.905 | 19.451 | +2.89% |
| repeated, 1,024 aliases | 88.946 | 89.252 | +0.34% |
| generic/callable control | 17.167 | 17.593 | +2.48% |
| resource/borrow control | 17.140 | 17.642 | +2.93% |
| ordinary type mismatch | 0.476 | 0.484 | +1.67% |

All iteration rows, including adverse outliers, are retained in
`check-system-2026-11-05.csv`. These rows are repeated observations within seven
process sessions, not independent per-iteration trials. Ranges overlap, but the
small adverse direction is consistent and is part of the storage tradeoff.

Allocation accounting is a separate build/run (`count` feature), with three
shuffled process trials. The allocator forwards allocation, zeroed allocation,
reallocation and deallocation to `System`, recording requested bytes; it does
not substitute an allocate/copy/free implementation for reallocation. It is
not used for the timing table. `program_live_bytes` is the signed change from
before checking to after the returned program is held, before validation and
destruction; it is not isolated flag-table memory or RSS. In a retained
128-alias session its first-to-last warm values are 118,914 to 134,792 bytes for
the vector and a constant 120,490 for the map. The 1,024-alias control is
376,650 to 403,856 versus a constant 405,418: the map can cost more on fresh,
dense data even though its storage stops following session history.

The source is parsed and loaded before timing; checking includes ownership and
unused-binding analysis. Every row validates the diagnostic count, and complete
serialized diagnostics agree across variants and process trials. The generic
and resource fixtures also produce identical emitted MIR and expected native
outputs under Debug and Release (twenty runs per variant/profile/fixture).
No generated-program throughput improvement follows.

## Alternatives measured

`storage.rs` separately compares the original vector, a map per binding, and
maps of 64-/256-byte dense pages. It constructs shuffled keys, adds independent
flag bits, then consumes two million mixed `has`/borrow queries with an
independent expected checksum. Cases include empty, one/four bindings,
aligned/unaligned ranges, dense cold/history-offset ranges, interior misses,
and widely separated singleton pages. Both borrow bits retain exclusive
precedence. System timing and allocator-counting samples are separate, seven
processes per case/representation; the complete final and corrected earlier
screen rows are retained in the `storage-*.csv` files.

For 128 bindings at a 16-million ID offset, requested live container storage is
32,000,102 bytes for the vector, 4,368 for the map and 212 for 64-byte pages.
For 128 singleton pages it is 6,553,604 / 4,368 / 12,560 respectively. At 8,192
dense bindings, pages are much smaller than a per-binding map, but hashed-page
lookup timings are similar and sparse pages pay for unused slots. The simple
map was selected for its tight bound and smallest implementation, rather than
adding page layout and allocation machinery. Direct vector lookups remain
faster in the microbenchmark; no lookup-speed improvement is claimed.

A shifted vector still allocates across gaps between cached standard IDs and
new user IDs. Reusing IDs or recycling the session would alter identity/lifetime
contracts. Sorted insertion can become quadratic because facts arrive from
unordered maps; bulk sorting would add a construction/finalization protocol.
None is required to correct this container's key-space mismatch.

## Reproduce

Linux x86_64, kernel 6.18.57, glibc 2.41, Intel Xeon Platinum 8573C VM, five
visible CPUs/four-CPU quota, 16 GiB limit. Measurement children were pinned to
CPU 0; the VM is not exclusive. Rust/Cargo 1.99.1, release opt-level 3, debug info,
no LTO/custom CPU flags, default unwind profile. Builds and source setup are
outside timers. No instruction-counter claim is made. The current suite-wide
baseline is `../baseline-2026-10-28.md`; these same-machine compiler controls
are the applicable before/after baseline for this storage correction.

Build the same harness against both trees (the baseline predates this harness):

```sh
git worktree add --detach .artifacts/binding-before 5ade79d71081246b35f9235595915b825336d6c0
mkdir -p .artifacts/binding-before/bench/perf
cp -R bench/perf/binding-flags .artifacts/binding-before/bench/perf/
RUSTFLAGS='' cargo +1.99.1 build --release --locked \
  --manifest-path .artifacts/binding-before/bench/perf/binding-flags/Cargo.toml \
  --target-dir .artifacts/binding-before-target
RUSTFLAGS='' cargo +1.99.1 build --release --locked \
  --manifest-path bench/perf/binding-flags/Cargo.toml \
  --target-dir .artifacts/binding-after-target
```

Generate fixed alias and invalid controls outside tracked source:

```sh
mkdir -p .artifacts/binding-inputs
python3 - <<'PY'
from pathlib import Path
p = Path('.artifacts/binding-inputs')
for n in (1, 128, 1024):
    s = 'fn sum(values: List[Int]) Int:\n'
    s += ''.join(f'    let alias{i} = values\n' for i in range(n))
    s += '    return ' + ' + '.join(f'alias{i}.length()' for i in range(n))
    s += ' + values.length()\n\nexport fn main() Int:\n'
    s += f'    return sum([1]) - {n + 1}\n'
    (p / f'aliases{n}.ms').write_text(s)
(p / 'invalid.ms').write_text(
    'export fn main() Int:\n    let _invalid: Int = "bad"\n    return 0\n')
# The tracked fixtures use canonical formatting. Remove the internal blank lines
# added by formatting to reconstruct the exact source bytes used in these samples.
for name in ('generic', 'resources'):
    text = Path(f'bench/perf/binding-flags/fixtures/{name}.ms').read_text()
    (p / f'{name}.ms').write_text(text.replace('\n\n    ', '\n    '))
PY
```

One repeated-session run, and its fresh-session control:

```sh
taskset -c 0 .artifacts/binding-before-target/release/ms-binding-flags-perf \
  .artifacts/binding-inputs/aliases128.ms 64
taskset -c 0 .artifacts/binding-after-target/release/ms-binding-flags-perf \
  .artifacts/binding-inputs/aliases128.ms 64
taskset -c 0 .artifacts/binding-after-target/release/ms-binding-flags-perf \
  .artifacts/binding-inputs/aliases128.ms 8 fresh
```

The full check matrix uses eight checks for each cold source (1/128 aliases),
64 for warm128, sixteen for warm1024 and each generic/resource/invalid control.
Use seven fresh processes per variant/case and retain every row. The recorded
order was shuffled with Python `random.Random(260018)` over
`(trial, variant, case)` in that order; per-case diagnostic output on stderr must
match exactly. The generator reconstructs the exact generic/resource input bytes from the
canonical fixtures; every CSV row records its source SHA-256.
Build with `--features count` into separate target directories for the three
allocation trials; do not mix those times into the native-allocator table.

For the container microbenchmark, run `ms-binding-flags-storage SHAPE TRIAL KIND`.
Shapes are `empty`, `one`, `four`, `unaligned`, `tiny`, `cold-dense`, `hot-tiny`,
`hot-dense`, `sparse`, `holes`; kinds are `dense`, `sparse`, `pages64`, `pages256`.
The final protocol shuffles seven trials with seed 2600. The earlier screen used
whole-byte lookup; the final controls exercise `has` and borrow precedence.

Initial exploratory timings that used the allocator trait's default realloc,
and a whole-check screen overlapping compilation, were rejected as timing
comparisons and retained privately. Their corrected allocation/isolated timing
runs above are the evidence used for selection. No outliers were deleted from
the accepted runs, and the singleton-page adverse result was retained.
