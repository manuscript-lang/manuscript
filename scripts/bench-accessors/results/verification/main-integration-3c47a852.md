# #521 String-map fixture migration and accessor composition

The parent authorized equivalent getter-syntax fixture corrections without
another permission stop. PR #516 remains draft and unmerged.

- Prior published head: `ce84ee861af0de8ed51530a62b999e96d507bc95`.
- Integrated main #521: `3c47a852d012246d61ba030440c79abf01a5e2b7`.
- Exact candidate: `091b80ddecff32590cec43dfdae730f0ce27e245`.

The prior published head completed [CI/CD #1215](https://github.com/manuscript-lang/manuscript/actions/runs/38679737706)
and [distributions #747](https://github.com/manuscript-lang/manuscript/actions/runs/38679737654)
successfully, including all required gates and six native distribution targets.
Its verified merge `804e0bce` had main `cd381fc4` and head `ce84ee86` as parents.
Main then advanced to #521 and GitHub reported the PR unmergeable.

Inspection found the same migration in the new String-map fixture: two
m.length() calls. The six-file incoming delta merged cleanly, preserving the
String-keyed helper expectations and existing accessor exclusions. Both new
calls now use m.length, retaining the fixture's assertions. No additional
production correction was authored beyond incoming main.

A targeted execution before the two-call correction rejected precisely those
old accessor calls; [raw expected-failure log](integration-3c47a852/getter-before.log).
The corrected native fixture passes with the affected suite. Map get/add remain
methods; their new String-keyed implementation still composes with live Map
accessors. Earlier Int-map, generic-record, primitive-literal, fallback, scope,
default and source-marker corrections remain intact. Error.message() and every
implementation remain methods.

## Fresh checks at 091b80dd

Pinned Go 1.25.1, Linux/amd64:

| Check | Result |
| --- | --- |
| Full lower/compiler/nativeabi/stdlib suites | PASS |
| Full runtime race | PASS, 32.133s |
| Focused native accessor/Map/generic/primitive-literal e2e and build | PASS, 20.944s / 12.655s |
| `make -o payload verify` | PASS |

The existing String-map native fixture preserves replacement-size, value,
missing/empty/empty-key lookup and mutation-during-iteration assertions. The
compiler's helper expectations, including accessor helper identities, remain
checked. No mirrored test or benchmark was added.

[Commands/provenance](integration-3c47a852/provenance.json),
[raw routine log](integration-3c47a852/verify.log), and
[named Go test inventory](integration-3c47a852/named-tests.json) are saved beside
this record. Comparing main `3c47a852` and candidate `091b80dd` yields 60 added and 87
updated tests. Historical benchmarks and coverage keep their original revisions.

The [independent exact-code review](integration-3c47a852/review-091b80dd.md)
returned **APPROVE**, with no blocker. Independent native source probes cover
String-map getter/argument order, Optional nesting and mutable payload aliases;
three compiler/lowering helper expectations pass. A bounded 1,000-step
String-specialized versus generic helper comparison passes under the race
detector, including copy-on-write, removal/index rebuild, live accessor reads
and cancellation. The report is retained unchanged (SHA-256
`f21c4638a1f931b09e6926fefe8fcbedaf581325ee23db6ad6ecc4e83a8d0f80`).

## Publication boundary

The prior green CI belongs to ce84ee86 over cd381fc4. New-head CI must establish
the current required language/book and all six native distribution gates, with
the actual tested merge parents recorded. Further identical getter-fixture
migrations remain authorized; material semantic conflicts must be reported.
Normal pushes only, no auth changes, force push or merge. Parent retains final
exact-head clearance and merge.
