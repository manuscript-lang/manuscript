# Bounded #518 integration with read-only accessors

PR [#516](https://github.com/manuscript-lang/manuscript/pull/516) remains draft and
unmerged. The parent specifically requested resolving #518's overlap.

- Prior published head: `919638e782cbd0662529d12d5b8cd401ceeac4c4`.
- Integrated main: `967e912751f97b6ff0ba029270f509e23639c56a`.
- Reviewed merge candidate: `35eb567e712ddf800df8095292a5d0af5ef683fe`.

The incoming delta changes five files for Int-keyed Map lookup/replacement.
The sole content conflict is in `TestTextLengthAndMapGetLowerWithoutBoxing`:
the resolution requires both `rt.StringLengthRead(` from the accessor migration
and `rt.MapGetPartsInt(` from #518. The new
`TestIntKeyedMapCallsKeepSemantics` has exactly two `m.length()` calls migrated
to `m.length`. Its replacement-size and mutation-during-iteration assertions
retain their original meaning.

No additional production-code correction was needed beyond the incoming #518
delta. The merged compiler retains accessor exclusions from callable collection
paths; the previously approved default-recursion, lexical evidence, source-marker
and boxed List fallback corrections remain present. Map.get/add remain methods,
List/Map observation accessors stay live, and Error.message() and every
implementation remain methods.

## Fresh verification

Pinned Go 1.25.1, Linux/amd64, at exact candidate 35eb567e:

| Check | Result |
| --- | --- |
| Full lower/compiler/nativeabi/stdlib suites | PASS |
| Full runtime race | PASS, 48.308s |
| Focused native accessor/collection/Int-map e2e and build | PASS, 51.005s / 15.803s |
| `make -o payload verify` | PASS |

The changed lowering test pins both helpers. The migrated native test exercises
Int map replacement, missing/empty lookup, live size and mutation while iterating;
the focused native and runtime suites cover accessor and collection composition.
No new test was needed for this three-line migration: the existing assertions
exercise the exact combined contracts.

[Provenance and exact commands](integration-967e9127/provenance.json),
[raw logs](integration-967e9127/verify.log), and the
[named Go test inventory](integration-967e9127/named-tests.json) are saved beside
this record. The inventory compares main `967e9127` with `35eb567e`: 60 added and 84 updated
tests. Historical benchmark and coverage evidence retains its original revisions;
no benchmark was rerun and no new performance claim is made.

The [independent exact-code review](integration-967e9127/review-35eb567e.md)
returned **APPROVE** for `35eb567e`, with no blocker. It independently checked the
combined helper expectation and executed both the incoming native fixture and a
source probe covering accessor receiver order, key/value evaluation order,
implicit Optional wrapping, nested absence, aliases and replacement iteration.
A deterministic 1,000-step typed-versus-generic Map helper probe passed under
the race detector, including copy-on-write, removal/index rebuild, live accessor
reads and cancellation. The report is retained unchanged (SHA-256
`85af935a7df6b77fa8bdeec1e4be6624a07d169da01ac35c1dc2cf13f9e73d05`).

## Publication boundary

The earlier head `919638e7` passed
[CI/CD #1206](https://github.com/manuscript-lang/manuscript/actions/runs/38677152909)
and [distributions #741](https://github.com/manuscript-lang/manuscript/actions/runs/38677152770)
over main d70b29be. Those results remain earlier-head evidence.
After the normal push, new exact-head required language/book and all six native
distribution checks must pass. Parent owns final exact-head clearance and merge;
no force push, auth changes or merge is included.
