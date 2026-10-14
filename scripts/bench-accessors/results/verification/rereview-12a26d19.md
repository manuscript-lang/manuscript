# Independent correction re-review

**APPROVE.** The sole P3 finding from the original independent review is resolved; no new finding in this correction.

Exact reviewed commit: `12a26d19687f371c18d11cdf1db1b7b35720bc71`.
Exact parent: `5107114ece3d72beb8ebfef9e1cdd5d1858b1dac`.
Read-only worktree: `/workspace/manuscript-accessor-review-fix`; clean status verified. No source edits made.

Reviewed the complete two-file diff (`4 insertions, 4 deletions`) from parent to commit. `optionalUseHint` now recommends the accessor spelling `is_some before unwrap()`. The existing comparison, arithmetic and expected-value Optional diagnostic cases each require that exact substring, which would fail with the removed `is_some()` spelling. The change leaves extraction methods callable and changes no runtime or checking behavior beyond remedy text.

Reviewer-executed checks:

- `git diff --check HEAD^ HEAD`: PASS.
- Pinned Go 1.25.1 `go test ./pkg/checker -run '^TestDiagnosticsStateCauseAndFix$' -count=1`: PASS (`0.065s`), with `GOCACHE=/tmp/manuscript-accessor-go-cache GOPATH=/tmp/manuscript-accessor-go GOFLAGS=-buildvcs=false XDG_CACHE_HOME=/tmp/manuscript-accessor-cache`.
- Compiled `/tmp/accessor-optional-hint.ms` using this exact checkout via `/tmp/accessor-probe.go`; actual diagnostic now reads: `expected Int, found Optional[Int]; Optional[Int] may be absent; unwrap it first with unwrap_or(default), is_some before unwrap(), or match`.

The original full feature review remains `/tmp/accessor-independent-review-5107114e.md`. Together, that approval and this narrow correction review cover the feature at `12a26d19687f371c18d11cdf1db1b7b35720bc71`. This is an independent code-review approval, not author self-approval or publication/merge authorization.

Limits: no repeated full e2e, coverage, race, distribution or platform suites for this diagnostic-only correction. The parent is separately completing its broader checks; those results are not claimed as reviewer-executed evidence. Any subsequent source change requires review of its exact diff.
