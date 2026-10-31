# Fresh main 8dd control follow-up

This repeats the byte-word/vector candidate on main 8dd79f417 with a rebuilt,
fixed compiler and source-matched native archives. The four-state experiment also
contains an **unaccepted** ASCII-normalization prototype: baseline, byte only,
ASCII only and both. Exact state patches, source/archive hashes, program hashes,
input templates and protocol records are retained. No binary/archive is published.
The prototype's code is a documentary patch, not part of the byte production PR.

All complete identities/outputs/counts/checksums validate: normalization 100 cases
and 7,200 rows (four native/two matched Rust variants, 12 balanced rounds); byte
220/7,040, lines16/512, reverse83/2,656 (four variants/eight balanced rounds).
The original reverse cohort flags byte-only ascii_mixed_n63. This caused the
second draft hold, separate from the earlier scalar-prefix boundary regression.
Two predeclared full83 same-binary repeats and a same-baseline-binary A/A run
followed. No producer or binary was changed between these phases.

| Word-only n63 phase | Median change | Paired delta ns | Slower pairs | Delta range ns |
| --- | ---: | ---: | ---: | ---: |
| original 8dd factorial | +6.63% | +9.76 | 7/8 | -12.24…26.08 |
| full repeat 1 | +2.21% | +3.44 | 5/8 | -14.84…14.54 |
| full repeat 2 | +1.49% | +3.24 | 6/8 | -21.06…43.57 |
| identical-baseline A/A | +5.01% | +15.98 | 3/4 | -5.84…29.86 |

The material penalty did not reproduce in either full repeat; a smaller persistent
cost remains possible because word medians remain slower. A/A has four pairs,
less power than the eight-pair comparisons. Its zero screening flags are not zero
variation. This does not prove unrelated workloads unchanged or the suite free
of regressions. The original unfavorable observation remains.

The original **combined prototype** also flags n64 reversal +5.33%, paired
+15.32 ns, 8/8 slower; its two full repeats change direction (-2.30%/-2.10%).
The ASCII-only prototype separately flags an early-Unicode4KiB reversal in repeat2,
absent in the preceding cohorts. All cases—not just the flagged ones—are retained.

The new normalization prototype has additional unresolved composition costs.
Original C0→both compatibility4096NFKD is +6.32%, paired +7.63 us,11/12 slower;
the baseline-inclusive repeat has a +5.05% median while its sign count does not
cross the descriptive screen. It remains unaccepted. Word-only is approximately
flat for this normalization case; this is not attributed to the byte operation.
Other same-binary normalization A/A flags and the complete controls remain as
noise evidence, not proof of equivalence. No backend/placement cause is claimed
and no padding or placement tuning was performed.

The byte production source remains the reviewed word/vector implementation. Its
correctness tests and all220 direct cases pass; targeted gains remain large.
Readiness review assesses the word-only evidence independently of the held ASCII
prototype. Required CI and final merged-main replay remain necessary. There is
no blanket clean claim for the whole assigned string lane.
