# Rejected second-pass codec experiments

These are measured prototypes on baseline
`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`, with the same Linux x86-64,
Rust 1.99.1 and LLVM 23.1.1 O3 setup as the adjacent JSON failure report.
They are not shipped changes or speedup claims. They are distinct from the earlier
input `.values()` removal, CSV parse concatenation, and closed limited-split work.

- CSV quote detection replaced a per-field scalar list with four existing ASCII
  `contains` checks, exact backslash-dot detection and first-scalar trimming.
  Common short plain fields slowed roughly 1.4–1.6× in the initial paired trials,
  while long fields improved. Reject the unconditional replacement.
- Native Base64 encoding replaced four character pushes with one ASCII byte batch.
  Collected instructions dropped for nonempty inputs, but longer generated-program
  controls remained mixed for tiny/empty values despite clear bulk benefits.
- A second encoder prototype processed complete three-byte groups and handled
  padding once, with an explicit empty return and exact-capacity calculation.
  It also failed to establish consistent common-path behavior. It uses no size
  threshold or padding/alignment tuning. Neither encoder prototype is retained.

All original paired samples, including warm-ups and mixed cases, are retained in
`initial.jsonl`, `batch-long.jsonl` and `groups-long.jsonl`; both wall and process
CPU clocks are present in the longer runs. Producer exit status, case identity,
operation count, positive timers and complete expected output were checked.
The scripts, program text, source/binary/archive hashes and native instruction
counts are retained alongside them. Process CPU does not eliminate frequency,
cache or all VM effects; the broad ranges remain material uncertainty.

The CSV experiment compiled before/after copies of the source as local modules;
its nominal type/module identities therefore differ from a rebuilt standard
library. This strengthens the reason to reject a mixed prototype rather than
claiming it is a measured production improvement. The native encoder experiments
used one compiler and explicit before/after production runtime archive overrides.

To reconstruct, use the pinned baseline and apply exactly one zero-context patch
with `git apply --unidiff-zero` in a disposable checkout. Source snapshots with
`.txt` suffixes are evidence, not benchmark-discovery inputs; copy them to the
paths expected by the retained driver when reproducing. Do not apply both native
encoder patches together. Benchmark startup/input generation and compilation are
excluded by the clocks. Raw Callgrind profiles remain local; their compact counts
and the collection command are retained in the surrounding codec protocol.

No CSV or native encoder production code from these experiments was committed.
A fresh attempt needs a new causal fix addressing the common-path tradeoff; a
remeasurement or layout adjustment alone does not resolve it.
