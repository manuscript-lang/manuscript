# Bounded #517 integration with read-only accessors

PR [#516](https://github.com/manuscript-lang/manuscript/pull/516) remains draft and
unmerged. The parent specifically requested composition with main #517; this
record does not reopen the stopped broad performance branch.

- Prior published head: `bc24cf9379f5320a0c41ba78392097e3f2d1b866`.
- Integrated main: `d70b29bec4379ae1ba4d8d605cac93c8f89e192f`.
- Clean merge: `0443f74c36d101575a6e964448d0d547f11c424a`.
- Corrected code and regression tests: `f97b511ea6978eb4e375df582819b788d8a6219a`.

## Composition and bounded correction

The incoming delta changes only `pkg/runtime/library_algorithms.go` and
`pkg/runtime/list_storage.go`: map/filter build results directly in selected
List storage and map uses a private writer that can fall back to boxing.
Accessor helpers already read current storage through Len/Get, so no accessor
declaration, migration spelling, compiler lowering or native ABI change is needed.

Independent review found a supported runtime compatibility regression in the
incoming filter: a primitive-labelled List may deliberately contain nonmatching
dynamic payloads in boxed fallback storage. The existing NewList constructor
tests establish this contract. Old filter preserved those values through NewList;
the incoming direct Append asserted their primitive types and panicked.
This is a runtime compatibility case, not a claim that ordinary checked source
can manufacture such a mismatched primitive payload.

Filter now boxes its private partial result before appending a retained payload
that does not fit. The existing map writer shares that conversion. Ordinary
Append behavior, callback traversal/guards/checkpoints, and scalar storage for
fitting payloads retain their contracts. No cache, constructor snapshot,
accessor inventory expansion or unrelated backend optimization was added.
Error.message() and every implementation remain methods.

## Regression coverage

- `TestListTransformResultsPreserveDynamicFallbackAndAccessorReads`: all four
  primitive identities, map/filter, nonmatching dynamic/Optional payloads,
  endpoint/length/empty reads, subsequent mutations and fresh outer storage.
  The exact final test fails against the original #517 two-file production
  overlay with an Append type assertion and passes with the correction.
- `TestAccessorsComposeWithTypedListTransformResults`: three called native
  source tests cover all four primitive results, live closures and endpoint
  reads after mutation, independent outer storage, empty-result absence and
  append, generic nested Optional payloads, shallow mutable aliases, and captured
  callback traversal while source accessors observe mutation.

The [current named Go test inventory](integration-d70b29be/named-tests.json)
compares main d70b29be with f97b511e using Go AST declarations: 60 added and
83 updated tests. The two tests above are the additions in this integration.

## Fresh local verification

Pinned Go 1.25.1, Linux/amd64. Every command below exited zero at f97b511e:

| Command | Result |
| --- | --- |
| `go test -race ./pkg/runtime -count=1 -timeout=10m` | PASS, 26.971s |
| `go test ./pkg/lower ./pkg/compiler ./internal/nativeabi ./pkg/stdlib -count=1` | All four packages PASS |
| Focused native accessor/collection e2e and build checks | PASS, 31.555s / 8.520s |
| Eight selected `TestCoreConformance` collection/Optional/error fixtures | PASS, 10.741s |
| `make -o payload verify` | PASS |

Exact commands, environment, target identities and exit statuses are in
[provenance](integration-d70b29be/provenance.json); raw logs are beside it.
The intentionally failing original-#517 overlay is causal regression evidence,
not a failed final gate.

The [independent exact-code review](integration-d70b29be/review-f97b511e.md)
returned **APPROVE** for f97b511e. It independently reproduced the incoming
filter failure and the prior implementation's passing behavior, checked the
final regression with only the original two production files restored, and ran
race probes covering first/middle/last/nil fallback, typed filter selection,
marked/unmarked callback cancellation, fault/admission identity and captured
mutation. Its extracted native source test passed all three cases. No blocker
remained. The saved report is unchanged (SHA-256
`1718a664baf6986927fbced15a93240dfb4f0955b3b43eeb53068904bb05265f`).

## Publication boundary

The previous head's [CI/CD run](https://github.com/manuscript-lang/manuscript/actions/runs/38675750436)
and [distribution run](https://github.com/manuscript-lang/manuscript/actions/runs/38675750434)
passed over main b2a288b1. They do not establish CI for this new integration.
After the normal push, required language/book and all six native platform
distribution targets must pass on the new PR head/merge ref.

The historical benchmark samples, baseline identities and 78.0% coverage record
remain unchanged and belong to their stated revisions. No new timing or
coverage claim is made for f97b511e. Parent coordinates exact-head clearance and
merge; no force push, authentication changes or merge is part of this work.
