# #520 primitive-list fixture migration and accessor composition

The parent authorized equivalent getter-syntax fixture corrections while keeping
the approved accessor migration coherent. PR #516 remains draft and unmerged.

- Prior published head: `2e29c5ccf6e98681d9d520164f120aad5b78fcba`.
- Integrated main #520: `cd381fc4570dcd5d2763ce6c3eb0ef5619238cda`.
- Exact candidate: `5e19ababf5cb59a65fc000a78f5b46cc38c55283`.

The prior published head's actual CI merge
`b8a12cd6bc0c3b91fe30d9e93dc68a9a8a182bcb` includes main #520, which adds
TestPrimitiveListLiteralsOwnFreshStorage with six obsolete length() calls.
Auditing that concrete CI merge found the identical migration before waiting for
another failed run. The three-file upstream delta merged cleanly. All six calls
now use .length; assertions and intended behavior are unchanged.

The preceding [CI failed job](https://github.com/manuscript-lang/manuscript/actions/runs/38679276363/job/116239863659)
subsequently confirmed exactly those six obsolete calls in the new fixture;
the [saved excerpt](integration-cd381fc4/prior-ci-failure.log) records its checked
merge and actionable diagnostics. The corrected native fixture passes below.

No additional production correction was authored beyond incoming #520.
Its primitive literal constructors still adopt fresh scalar slices, and its
scalarSiblings path retains the established source-order handling. The accessor
helpers read the same authoritative List storage, preserving current length,
empty/endpoint observations, Optional absence and mutable aliases. Prior #519
typed/boxed generic-record composition, #517 fallback and other approved fixes
remain intact. Error.message() and every implementation remain methods.

## Fresh local checks at 5e19abab

Pinned Go 1.25.1, Linux/amd64:

| Check | Result |
| --- | --- |
| Full lower/compiler suites | PASS, 0.351s / 2.585s |
| Focused runtime list/accessor race suite | PASS, 1.839s |
| Focused native list/accessor/generic/struct/Int-map e2e and build | PASS, 40.751s / 23.982s |
| `make -o payload verify` | PASS |

The migrated existing test checks fresh outer storage, lengths across all four
primitive representations, empty construction, append, equality and nested lists.
No mirrored test or benchmark was added. Historical benchmark/coverage files and
their revision scope remain unchanged.

[Commands/provenance](integration-cd381fc4/provenance.json),
[raw routine log](integration-cd381fc4/verify.log), and
[named Go test inventory](integration-cd381fc4/named-tests.json) are saved beside
this record. Main `cd381fc4` versus candidate `5e19abab` has 60 added and 86 updated
tests, including the six-call fixture migration as an updated test.

The [independent exact-code review](integration-cd381fc4/review-5e19abab.md)
returned **APPROVE**, with no blocker. The incoming fixture and three independent
source tests passed in ordinary and Debug compilation, covering all four owned
primitive kinds, getter/match order, try barriers, fresh storage, boxed aliases,
Optional nesting and negative zero. Lowering guard/large-boundary checks and
the prior #517 fallback/accessor regression passed, including race coverage.
The report is retained unchanged (SHA-256
`c65922e318b10e9e6e3d4469025621bfdbe1f0b714549df9bc4181f3112b42af`).

## Publication boundary

The prior CI merge's fetched parents are main `cd381fc4` and head `2e29c5cc`; the
connector's normalized base field can lag that physical parent. New-head CI must
be reported with its actual tested merge identity and parents. Equivalent new
getter-syntax fixture failures remain within the authorized migration and need
no additional permission stop; material semantic conflicts must be reported.
Normal pushes only; no auth change, force push or merge. Parent retains final
exact-head clearance and merge.
