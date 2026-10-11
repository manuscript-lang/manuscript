# Implementation coverage

The implementation follows the design book on `main` and its [core language conformance cases](design/compiler/conformance/core-language.md). It is a Go compiler with a native Go backend and an embedded runtime. Go 1.25 or newer is required; there are no third-party Go dependencies. This document distinguishes implemented behavior from additional contracts and tooling described in the book.

## Language and checking

- UTF-8 source with original byte positions across BOM/CRLF normalization, ASCII identifiers, exact four-space suites, comments, delimiter continuation, numeric literals, escapes, and checked interpolation.
- Exact intrinsic types, nominal immutable records and alternatives, generic types/functions, operation contracts, explicit implementations, plain/shared views, signature and argument-label checking, orphan and overlap rejection, and structural sharing/equality/hashing eligibility.
- Named calls, function values, suite closures, snapshot captures, and rejection of captured assignment. Sharing proofs are retained on eligible source/native functions and closures and erased at plain function parameters, results, fields, and generic forwarding.
- Local inference, contextual constructors, invariant generic applications, bounds, guarded recursive layouts, and finite generic call specialization. Generic inference uses independently typed arguments; an expected result does not supply missing type arguments.
- Bindings, name assignment, list/record destructuring, branching, loops, exhaustive alternative matching, returns, assertions, loop exits, lexical `with`, and exact-error `try` propagation. Return completeness includes `Never` and conservative loop rules.
- Explicit standard imports, exported-symbol visibility, relative imports and aliases, canonical module identity, root containment after symlink resolution, cycle rejection, and public type visibility.
- Conservative transitive effects (`read`, `write`, `external-call`, `unknown`), including implicit cleanup and nested closure bodies. Indirect calls remain unknown. These summaries do not claim to enumerate every capability retained by a value.

`syntax`, `lexer`, `parser`, and `checker` are independent packages. Checked programs retain syntax, resolved types/operations, binding identities, captures, selected cleanup methods, and effects. Diagnostics have stable code families, phases, file/line/column, and original byte offsets. Failed checking produces no generated program.

## Standard library and runtime

| Facility | Implemented behavior |
| --- | --- |
| Numbers | Checked signed 64-bit integers, IEEE binary64 floats, and 34-digit Decimal arithmetic with ties-to-even rounding and exact literal validation |
| Immutable data | List, insertion-ordered Map and Set, MapEntry, Bytes, UTF-8 conversion, Optional, Result, and `map_error` |
| Time | Duration construction/arithmetic, monotonic Clock/Instant domains, sleep, and operation deadlines |
| Cleanup | Checker-selected contract dispatch, registration of delivered `with` values, reverse lexical release on every exit, shielded cleanup, primary/secondary fault preservation, and removal of completed cleanup actions |
| Joined work | Heterogeneous literal `parallel` packs, bounded ordered `parallel_map`, cancellation checkpoints, deadlines, sibling cancellation on faults, and joining before completion |
| Background | Bounded admission/history, fixed construction parent, cancellation, serialized reporting, bounded diagnostic fallback, optional drain, concurrent idempotent close, and nested-service joining |
| Queues and state | Bounded FIFO queues with cancellable waits, close/wakeup/drain semantics, and synchronized shareable State with atomic get/set/swap |
| Pools and leases | Fixed resource pools, cancellable acquisition, guarded contract views, stale-alias rejection, single capacity return, operation cancellation/joining, and reverse owned-resource release |
| Builders | Local List/Map/Set/Bytes/String builders, immutable sealed snapshots, idempotent freeze, and rejection of mutation after sealing |
| CLI capabilities | Explicit Process arguments/environment, streams, read-only files, monotonic clock, network, commands, checked exit codes, signal cancellation, joined shutdown, and host-root cleanup |
| HTTP | Explicit Network authority; bounded buffered requests/responses, shared handler proofs, admission/body/output limits, timeout/disconnect cancellation, fault isolation, and grace/cancel/join shutdown |
| Subprocesses | Explicit Commands authority, joined execution, timeout, aggregate output bounds, captured bytes, exit status, and domain errors; process-group cancellation on platforms exposing that facility |
| Native acquisition | Undelivered files, pool leases, and HTTP servers are disposed if cancellation wins before delivery |

The exact new library APIs and boundary behavior live in the canonical [queue](design/standard-library/data-and-io/queues.md), [state/pool](design/standard-library/data-and-io/synchronized-state.md), [builder](design/standard-library/data-and-io/builders.md), [HTTP](design/standard-library/hosts/http.md), and [subprocess](design/standard-library/data-and-io/streams.md) pages. Source cannot manufacture native host authority.

The backend lowers functions and control flow to Go with type-erased runtime values after static checking. Generics use runtime type keys and coherent implementation dispatch; concrete Go layouts and machine-code monomorphization are not implemented. Map and Set use ordered linear storage. Pollable stream I/O supports cancellation/deadlines and concurrent close. Uncooperative native code or nonpollable I/O can still delay joining; forced termination does not constitute successful cleanup.

## Commands, builds, and source tools

`ms check`, `build`, `emit`, `run`, `test`, `inspect`, and `diagram` accept a module or project `ms.toml`. Project configuration supports `[project]` and `[aliases]` with strict keys. Standalone modules use their containing directory as the import root. Applications export nongeneric `fn main(process: Process) -> Int`.

`ms lock ms.toml` explicitly records compiler/frontend/runtime content and the selected Go toolchain/target in `ms.lock`. Native project builds reject missing or mismatched pins. Check/emit/source inspection do not need pins. Native artifacts have verified cache entries and `<executable>.ms-build.json` with source/configuration and executable hashes. Unchanged outputs are not rewritten. `compiler.VerifyBuild` checks binary/source identity. This establishes deterministic generated source and artifact identity, without promising byte-identical binaries across environments. Parsing and checking still run before an artifact cache hit.

`ms emit` produces one self-contained Go file with its runtime. Native builds use `-trimpath` without downloading runtime dependencies. Generated source has Go line directives, and programming faults accumulate source function positions. `--debug` disables optimization/inlining while retaining native symbols.

`ms fmt file.ms` validates syntax before atomically replacing a file and preserves comments and literal spellings. `--check` reports formatting drift without writing. `ms check --json` emits format-1 diagnostics. `ms inspect` emits checked entities, generated declaration names, source hashes, original-byte statement header spans, call sites, and effects. `ms diagram` emits their static Mermaid call graph, including implicit cleanup; neither command represents a runtime trace.

`ms test` executes test blocks in the reachable import graph in dependency/source order with `file::name` labels. Each test has a fresh execution lifetime; services join before the next test. Faults fail that test and remaining tests continue. Builds check test bodies but omit their execution code. Duplicate display names are allowed. Tests have no implicit Process authority. Declaration-only fixtures establish parse/check/build acceptance, not behavior of uncalled functions.

## Remaining design work

The book's [outstanding decisions](design/compiler/conformance/scope.md#outstanding-decisions) remain authoritative. The following parts are not implemented:

- External native adapter manifests/ABI, `[adapters]` loading, custom host distributions, and adapter/dependency pins.
- HTTP clients, streaming responses, WebSocket/session hosts, interactive subprocess streams, and uniform cross-platform descendant supervision.
- Full incremental frontend/package compilation, concrete native generic layouts, precise retained-authority classification, and native adapter effect declarations.
- Transactional structural edits, rich diagnostic spans/related locations, architecture diffs, runtime trace transport, complete local-value metadata, and Delve integration.
- Test discovery globs, identity beyond display labels, authority injection, and expected-fault assertions, which need the runner contract finalized.

The language core, supplied standard APIs, compiler commands, and native conformance tests are usable now. The coverage above is not a claim that every future facility in the design book is complete.

## Verification

```sh
go test ./...
go test -race ./runtime ./checker ./compiler ./tooling
go vet ./...
go test ./parser -run '^$' -fuzz FuzzParse -fuzztime 10s
go test ./compiler -run '^$' -fuzz FuzzCompile -fuzztime 10s
```

Native end-to-end tests compile accepted syntax and execute test bodies; rejected cases cover typing, visibility, bounds, captures, sharing, and service boundaries. Observable tests cover evaluation order, numeric faults, cleanup exits, SIGTERM child-before-parent shutdown, HTTP, subprocesses, source tooling, and unusual module filenames. Runtime tests use barriers/channels for concurrent state transitions; cache tests exercise pin mismatches, corruption, stale sources, and unchanged outputs. CI runs formatting, vet, the complete suite, race tests, and the hello project.
