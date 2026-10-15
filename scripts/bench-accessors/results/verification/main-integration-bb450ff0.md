# #519 fixture migration and generic-record accessor composition

PR [#516](https://github.com/manuscript-lang/manuscript/pull/516) remains draft and
unmerged. The parent explicitly authorized fixing this getter-syntax fixture
failure as part of the approved accessor migration, including further equivalent
fixture migrations without another approval stop.

- Prior published head: `092442a6f4e7b8946f2a3f69a6c466e710a6b593`.
- Integrated main #519: `bb450ff03259cd2cb606581fe7d53805911a6285`.
- Exact candidate: `10414283904dbb15f2a2a7f2bb50733fead1d192`.

The prior [failed CI job](https://github.com/manuscript-lang/manuscript/actions/runs/38678294519/job/116236810694)
checked merge `21e5bd01` over main #519 and rejected its new
TestGenericRecordInstantiationsKeepSemantics fixture. The assertion called
`items.v.length()`; the actionable diagnostic correctly required
`items.v.length`. The [saved excerpt](integration-bb450ff0/prior-ci-failure.log)
preserves the exact failure and checked identity.

The three-file #519 delta merged cleanly. The only authored code correction is
that single getter-call migration in `tests/e2e/generic_structs_test.go:45`.
The intended list-field assertion remains length == 3. Incoming typed concrete
generic-record planning/emission stays intact; no redesign or additional
production correction was made. All earlier approved accessor/default/cache,
source-marker, boxed List fallback and Int-map compositions remain present.
Error.message() and every implementation remain methods.

## Fresh checks at 10414283

Pinned Go 1.25.1, Linux/amd64:

| Check | Result |
| --- | --- |
| Full lower/compiler suites, count=1 | PASS, 0.379s / 1.754s |
| Focused native accessor/generic/struct/Int-map e2e and build | PASS, 9.866s / 4.641s |
| `make -o payload verify` | PASS |

The existing changed native fixture verifies the exact intended behavior; no
additional mirrored test was added. Runtime implementation files did not change,
so the earlier full runtime race at `35eb567e` remains prior-head evidence rather
than being relabeled as a fresh run here. No benchmark was rerun.

[Exact commands and provenance](integration-bb450ff0/provenance.json),
[raw routine log](integration-bb450ff0/verify.log), and
[named Go test inventory](integration-bb450ff0/named-tests.json) are saved beside
this record. Comparing main `bb450ff0` with `10414283` yields 60 added and 85 updated
tests, including the new fixture's migration as an updated test.

The [independent exact-code review](integration-bb450ff0/review-10414283.md)
returned **APPROVE**, with no blocker. Five independent called source tests and
emitted-Go inspection cover typed and boxed generic record accessors, default
constructors, shallow cloning/live aliases, Optional nesting, module-local view
evidence, and complete late factory registration. The report is retained
unchanged (SHA-256
`1ed3e886f3c6a108f292a9db70da1cda1cf3f4b9e16c799a379b554440ff168d`).

## Publication boundary

The prior head's [distribution run](https://github.com/manuscript-lang/manuscript/actions/runs/38678294488)
passed all six native targets. Its language run failed the now-corrected #519
fixture. Neither is relabeled as new-head CI. Following a normal push, current
required language/book and native platform/distribution CI must pass. Identical
old-getter fixture failures remain within the authorized migration; material
semantic conflicts must be reported. No force push, auth changes or merge is
part of this work. Parent retains final exact-head clearance and merge.
