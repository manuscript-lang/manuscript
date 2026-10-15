# Pre-publication integration with main #513–#515

The user authorized a normal branch push and draft PR. Merge remains held for
parent coordination; no force push or authentication changes are authorized.

Preserved implementation/evidence: `3d3ba796559f165bf2c6a81c91b03608745d6db3`.
Integrated main: `b2a288b19bb7acce05165d94b98b4a5c519bb09f`.
Independently approved code: `df5f1206e7e6231e861a913d41ca78448a26fa86`.

The [exact integration review](prepublication-main-b2a288b1/review-df5f1206.md)
approved the 12-file delta. The earlier recursion/default-expression and lexical
view-scope fixes remain intact. Accessors stay excluded from callable fast paths,
including the new standard contract operation path. New upstream test calls use
the approved accessor names; parsing, to_bytes, callback transformations and
Error.message() remain methods. The migration inventory remains 56 getters plus
the three existing Int properties.

Integration also repairs a proven #514 source-marker regression: an eligibility
probe lowered a standard-contract receiver into a discarded bound expression,
then lowered it again. A nested Clock receiver containing a callable failed with
`lost generated source directives: printed 8 of 10`. The old-path probe fails;
the integrated path compiles and executes. Full argument arity/order already
proves every default is supplied, so the discarded lowering is unnecessary.
`TestAccessorReceiversComposeWithStandardContractOperations` checks the nested
receiver and three live accessor reads while switching native/source/native
Clock implementations at one operation site.

Fresh affected checks on the approved code, pinned Go 1.25.1, Linux/amd64:

- Full lower/compiler/checker/runtime/nativeabi/stdlib package suites: PASS.
- Focused native e2e and build suites: PASS, 35.385s and 21.580s.
- Full runtime race: PASS, 41.910s.
- `make -o payload verify`: PASS, including tooling/LSP, standard sources,
  documentation policy, examples, static and repository checks.
- Independent review probes: exact-main source-marker control fails, integrated
  native execution passes; standard Error.message local-view dispatch passes;
  native operation pointer identity, concurrency, cancellation and stale-guard
  checks pass under the race detector. No new blocker was found.

Logs, review, [complete named Go test inventory](prepublication-main-b2a288b1/named-tests.json)
and [provenance](prepublication-main-b2a288b1/provenance.json) are retained beside
this record. Later changes for publication update only documentation/evidence;
the reviewed compiler/runtime/test code remains unchanged.

The [preceding integration evidence](main-integration-9dcc0bae.md) records complete
Linux build/e2e, runtime/LSP race, native Go/DAP debugging, eight bounded fuzz
targets, standalone distribution and book checks at their exact earlier code
identities. The 52-workload comparison uses historical method baseline 1383851e;
the later 80 guard/Logger records compare 1383851e with 800547bb. These numbers
are historical evidence, not new timing measurements of df5f1206. Coverage 78.0%
belongs to historical 12a26d19. No measurements or historical files were rewritten.

PR CI must establish current-head macOS/Windows host execution, native ARM
distribution compatibility, full required language/book checks and all six
distribution target checks. Upstream-main CI is separate from accessor-branch CI.
The parent will coordinate final exact-head clearance and merge.
