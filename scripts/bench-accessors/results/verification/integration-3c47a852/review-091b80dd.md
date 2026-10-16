# Independent bounded main #521 composition review

APPROVE exact merge `091b80ddecff32590cec43dfdae730f0ce27e245`, integrating main `3c47a852d012246d61ba030440c79abf01a5e2b7` (#521) over published parent `ce84ee861af0de8ed51530a62b999e96d507bc95`. No concrete blocker was established. This is an independent exact-code review, not author self-approval, publication or a PR merge action.

Read the complete six-file first-parent diff, updated compiler helper expectations, and composition with existing accessor guards and Int-map paths. Exact source was exported with git archive into `/workspace/manuscript-accessor-review-main521`; probes/generated programs remain under `.artifacts/reviewer-091b80dd`. No primary files or production source were edited. Independently checked no pkg/internal/tests changes after the candidate; later primary changes are evidence/documentation only.

## Composition and contracts

The two old length() calls in the new String-map fixture are migrated to approved length reads, with receivers/assertions unchanged. No authored production changes accompany incoming main.

Lowering extends the existing primitive Int branch to checked primitive String keys while retaining exact native Map operation eligibility, arity/label ordering and accessor exclusions. primitiveEqualityType excludes nominal types, contract views and type variables, so custom/scoped key behavior remains on the generic path. The generalization retains receiver sequencing before key and checked argumentValue conversion for the value before calling MapWithEntryString. Reordered calls retain ordinary dispatch; compiler tests continue checking that distinction.

MapGetPartsString preserves the existing matched lookup payload/presence ABI. A present Optional.none remains distinct from an absent key, and mutable payload identity is unchanged. Nonmatched MapGet remains on its existing path.

lookupString is the existing lookupKey String case without the type switch: empty handling, derived-index validation/rebuild, String key equality and stable id-to-position conversion are unchanged. keyContext already returns the original Execution for String keys, so the specialized path omits no required lexical context. MapWithEntryString retains ownEntries before replacement and keyAppended after insertion, preserving captured iteration, insertion order, live length and index updates. Both new helpers retain the generic path's admission cancellation checkpoint and return semantics; no delivery checkpoint or callback behavior changes.

The previously reviewed accessor helpers, scope-aware method cache, source-marker/default-cycle corrections, #517 boxed transform fallback, #519 generic structs and #520 owned literal semantics remain untouched. Existing StringLengthRead and Int helper expectations remain present; the modified compiler expectations correctly name the new String add helper.

## Independent focused evidence

Pinned `/workspace/manuscript-accessor-design/toolchain/go/bin/go`, bin first in PATH; GOCACHE=/tmp/manuscript-accessor-go-cache, GOPATH=/tmp/manuscript-accessor-go, GOFLAGS='-buildvcs=false -p=2', XDG_CACHE_HOME=/tmp/manuscript-accessor-cache. Temporary build files used the review snapshot's `.artifacts/go-tmp` to avoid /tmp pressure.

- `git diff --check 091b80dd^1 091b80dd`: PASS.
- Independently extracted/compiled the migrated new String-map fixture and executed emitted Go against exact runtime: PASS, `1 tests, 0 failed`, including empty String key and mutation during iteration.
- Independently compiled/executed reviewer-owned String-key order-alias.ms: PASS, `1 tests, 0 failed`. It checks accessor receiver evaluation exactly once before a key expression switches the selected map, matched get capturing the old receiver, key capture before a value reassigns its local, implicit Optional wrapping, nested Optional.none, mutable List payload aliases and replacement during iteration. Emitted code uses MapWithEntryString/MapGetPartsString with ReadAccessor as the sequenced receiver, so this exercises the new paths rather than only a generic control.
- `go test ./pkg/compiler ./pkg/lower -run 'TestDirectKeyedAndStringLowering|TestMapAddDirectAndReorderedLowering|TestTextLengthAndMapGetLowerWithoutBoxing' -count=1`: PASS, compiler0.136s/lower0.279s. This covers updated String helper counts, reordered fallback and retained StringLengthRead/Int matched-get expectations.
- `go test -race -overlay .artifacts/reviewer-091b80dd/probe-overlay.json ./pkg/runtime -run '^TestReviewerStringMapFastPathsMatchGeneric$' -count=1`: PASS, 1.047s. Reviewer-only test compares specialized and generic helpers over 1000 deterministic mutations/removals/replacements, shared-entry copy-on-write and direct backing replacement/rebuild. It checks insertion order, payload pointer identity, live accessor length, 52 key lookups per step, captured entries surviving replacement, empty lookup absence and cancelled read/write nonmutation. Only test source is overlaid; production source remains exact.

Read primary completed logs in `.artifacts/integration-main521`: lower/compiler/nativeabi/stdlib all pass (0.283s/1.740s/0.007s/2.088s); full runtime race PASS32.133s; native e2e/build PASS20.944s/12.655s; routine verify completes. The primary also retained the prior actual fixture failure showing the two obsolete getter calls. These are primary gate results, not independently duplicated broad runs.

## Limits

Linux/amd64 focused execution only. No redesign, benchmark rerun, new performance claim or unrelated baseline integration. Previous measurements retain their exact revision scope. The mutation comparison is bounded and does not prove every map state or unsupported concurrent mutation. No primary source edits, push, publication, PR update or merge performed by this reviewer. Later production changes require their own exact review; equivalent fixture-only getter migrations remain separately authorized by the user.
