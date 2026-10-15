# Independent bounded main #518 integration review

APPROVE exact merge `35eb567e712ddf800df8095292a5d0af5ef683fe`, integrating main `967e912751f97b6ff0ba029270f509e23639c56a` (#518) over published parent `919638e782cbd0662529d12d5b8cd401ceeac4c4`. No concrete blocker was established. This is an independent code-review judgment, not author self-approval, publication or a merge action.

Reviewed the complete five-file first-parent diff and relevant main-to-merge resolution. Exact source was exported with git archive into `/workspace/manuscript-accessor-review-main518`; reviewer probes and generated programs remain under `.artifacts/reviewer-35eb567e`. No production source or primary worktree files were edited. Independently checked no pkg/internal/tests changes after the candidate; later primary changes are evidence/documentation only.

## Composition and semantics

The conflict resolution correctly retains both StringLengthRead and MapGetPartsInt in the lowering expectation. The two incoming m.length() calls are migrated to approved accessor syntax without changing their assertions. Native accessor helpers, classification guards, default-cycle analysis, scope-aware method caching, standard-contract receiver correction, and the reviewed #517 boxed-result fallback remain untouched.

The new add fast path requires the existing native Map add identity, correct arity/label order, and a checked primitive Int key type. primitiveEqualityType excludes nominal types, views and type variables; source/custom equality continues through the generic paths. Receiver and key are sequenced before the value, and argumentValue remains responsible for checked Optional conversions of the value. Reordered calls keep their existing fallback.

The matched get fast path likewise evaluates its receiver before the key and returns a payload/presence pair. MapGetPartsInt preserves the distinction between an absent key and a present Optional.none payload. Returned mutable payloads remain the same reference.

lookupInt is the existing lookupKey Int branch with the type switch removed. It retains empty handling, derived-index validation/rebuild and stable-id-to-position conversion after removals. Existing keyContext already returns the original Execution for Int keys, so omitting scope transport changes no context or custom dispatch semantics. MapWithEntryInt retains ownEntries before replacement and keyAppended after insertion, preserving captured iteration, insertion order and derived-index maintenance. Its return value remains the mutable receiver. Both new runtime entrypoints retain the generic path's admission cancellation checkpoint; neither introduces or removes a delivery checkpoint or callback.

## Independent evidence

Pinned `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, bin first in PATH; GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS='-buildvcs=false -p=2', XDG_CACHE_HOME=/tmp/manuscript-accessor-cache throughout.

- `git diff --check 919638e7 35eb567e`: PASS.
- `go test ./pkg/lower -run '^TestTextLengthAndMapGetLowerWithoutBoxing$' -count=1`: PASS, 0.223s. The conflict test requires both accessor StringLengthRead and specialized MapGetPartsInt.
- Independently extracted and compiled the incoming Int-map source fixture with the exact compiler, then ran emitted Go against exact runtime: PASS, `1 tests, 0 failed`.
- Independently compiled/executed reviewer-owned `order-alias.ms`: PASS, `1 tests, 0 failed`. It checks an accessor receiver read exactly once before a key expression switches the selected Map; direct matched get captures the old receiver before that switch; an earlier key is captured before an effectful value reassigns its local; implicit Optional wrapping retains a mutable List alias; present inner none stays distinct from absent outer none; and replacement during iteration retains the captured iteration count and live length. Emitted code uses MapWithEntryInt and MapGetPartsInt with ReadAccessor as the sequenced receiver, confirming these checks exercise the new paths.
- `go test -race -overlay .artifacts/reviewer-35eb567e/probe-overlay.json ./pkg/runtime -run '^TestReviewerIntMapFastPathsMatchGeneric$' -count=1`: PASS, 1.045s. Reviewer-only test compares new typed helpers with existing generic helpers over 1000 deterministic mutations, removals, replacements, shared-entry copy-on-write and direct backing replacement/rebuild. It compares insertion order, payload pointer identity, live accessor length and 53 key lookups after each step. It separately checks captured entries survive replacement, empty lookup absence, cancelled reads/writes and nonmutation after cancelled insertion. Only test source is overlaid; production source remains exact.

Read the primary's completed affected logs in `.artifacts/integration-main518`: lower/compiler/nativeabi/stdlib all pass; full runtime race PASS48.308s; focused native e2e/build PASS51.005s/15.803s; make verify completes with source documentation, LSP/tooling, examples and license checks. These are primary results, not independently duplicated broad suites.

## Limits

Linux/amd64 focused execution only. No redesign, benchmark rerun, new speedup claim or baseline chasing. Earlier performance records retain their exact historical revisions. The randomized comparison is bounded and does not prove every possible map mutation or unsupported concurrent access. No primary source edits, push, publication, PR update or merge performed by this reviewer. Subsequent production changes need their own exact review.
