# Implementation coverage

This page tells you what the current compiler and runtime support and what remains design work. The compiler is written in Go and builds native executables through a Go backend. Release binaries embed reduced Go 1.25.1 build tools and references; source builds prepare them automatically with `make build`. WebSocket and public-suffix dependencies are pinned and vendored, so native builds need no package downloads.

Start with [your first program](design/getting-started.md) for a walkthrough. Use the [design book](design/_index.md) for language rules and the [conformance fixtures](design/compiler/conformance/core-language.md) for accepted and rejected examples.

## Language and checking

- UTF-8 source with original byte positions across BOM/CRLF normalization, ASCII identifiers, exact four-space suites, comments, delimiter continuation, numeric literals, escapes, and checked interpolation.
- Exact intrinsic types, nominal immutable records and alternatives, `type` records/alternatives, generic types/functions, `interface` operation contracts, explicit implementations with inherited generic parameters and bounds, contract views, signature and argument-label checking, module-local extensions for imported source types and overlap rejection, and universal sharing and structural equality/hashing eligibility.
- Calls with optional labels for single-parameter functions and mandatory labels for multi-parameter functions and constructors, per-call default argument expressions on source functions and methods, function values, suite closures, snapshot captures, and rejection of captured assignment. All function values may be shared through parameters, results, fields, collections, and generic forwarding.
- Local inference, contextual constructors, invariant generic applications, bounds, guarded recursive layouts, and finite generic call specialization. Generic inference uses independently typed arguments; an expected result does not supply missing type arguments.
- Bindings, name assignment, list/record destructuring, branching, loops, exhaustive alternative matching, returns, loop exits, lexical `with`, and exact-error `try` propagation. Return completeness includes `Never` and conservative loop rules.
- Explicit standard imports, exported-symbol visibility, relative imports and aliases, canonical module identity, root containment after symlink resolution, cycle rejection, and public type visibility.
- Conservative transitive effects (`read`, `write`, `external-call`, `unknown`), including implicit cleanup and nested closure bodies. Indirect calls remain unknown. These summaries do not claim to enumerate every capability retained by a value.

`syntax`, `lexer`, `parser`, and `checker` are independent packages. Checked programs retain syntax, resolved types/operations, binding identities, captures, selected cleanup methods, and effects. Diagnostics have stable code families, phases, file/line/column, and original byte offsets. Failed checking produces no generated program.

## Standard library and runtime

| Facility | Implemented behavior |
| --- | --- |
| Numbers | Checked signed 64-bit integers, IEEE binary64 floats, and 34-digit Decimal arithmetic with ties-to-even rounding and exact literal validation |
| Immutable data | List, insertion-ordered Map and Set, MapEntry, Bytes, UTF-8 conversion, Optional, and Result |
| Time | Duration construction/arithmetic, monotonic Clock/Instant domains, sleep, and operation deadlines |
| Cleanup | Checker-selected contract dispatch, registration of delivered `with` values, reverse lexical release on every exit, shielded cleanup, primary/secondary fault preservation, and removal of completed cleanup actions |
| Joined work | Heterogeneous literal `parallel` packs, bounded ordered `parallel_map`, cancellation checkpoints, deadlines, sibling cancellation on faults, and joining before completion |
| Background | Bounded admission/history, fixed construction parent, cancellation, serialized reporting, bounded diagnostic fallback, optional drain, concurrent idempotent close, and nested-service joining |
| Queues and synchronization | Local FIFO queues with optional capacity, immediate full/empty results and explicit synchronization for shared use; Synchronized values with cancellable lock acquisition, scoped guards, atomic get/set, stale-alias checks, and reentry detection |
| Pools and leases | Fixed resource pools, cancellable acquisition, guarded contract views, stale-alias rejection, single capacity return, operation cancellation/joining, and reverse owned-resource release |
| Builders | Synchronized List/Map/Set/Bytes/String builders, immutable sealed snapshots, idempotent freeze, and rejection of mutation after sealing |
| CLI capabilities | Explicit Process arguments/environment, streams, read-only files, monotonic clock, network, commands, checked exit codes, signal cancellation, joined shutdown, and host-root cleanup |
| HTTP | Explicit Network authority; bounded buffered requests/responses, ordinary handlers, admission/body/output limits, timeout/disconnect cancellation, fault isolation, and grace/cancel/join shutdown |
| Subprocesses | Explicit Commands authority, joined execution, timeout, aggregate output bounds, captured bytes, exit status, and domain errors; process-group cancellation on platforms exposing that facility |
| General-purpose packages | Strict codecs/binary numbers, scalar text, Float math/BigInt, exact JSON, CSV/URL/HTML, sequential collection algorithms, hashes/HMAC/PBKDF2/AES-GCM/Ed25519, compression and ZIP/TAR, bounded stream helpers, structured logging |
| Additional CLI roots | FileSystem read/write/copy/stat/list/directories/links, WallClock/Timestamp, System info/environment and cryptographic Entropy |
| Network clients and sockets | Buffered/streaming HTTP/1.1/HTTP/2 clients and servers, pooled transports/cookies/redirects, WebSocket sessions, TCP/Unix/TLS sockets and mutual TLS, bounded DNS record lookup, scoped resolver/policy and cancellation/close joining |
| Native acquisition | Undelivered files, lock guards, pool leases, and HTTP servers are disposed if cancellation wins before delivery |

The expanded package APIs and boundary behavior live in [general-purpose packages](design/standard-library/packages/_index.md); their types and signatures live in pinned Manuscript source declarations, with native ABI validation. The original host/service APIs and boundary behavior live in the canonical [queue](design/standard-library/data-and-io/queues.md), [synchronization/pool](design/standard-library/data-and-io/synchronized-state.md), [builder](design/standard-library/data-and-io/builders.md), [HTTP](design/standard-library/hosts/http.md), and [subprocess](design/standard-library/data-and-io/streams.md) pages. Source cannot manufacture native host authority.

After checking source, the backend translates functions and control flow into Go. Values use runtime representations rather than distinct concrete Go layouts for every source type. Generics use runtime type keys and coherent implementation dispatch; concrete Go layouts and machine-code monomorphization are not implemented. Map and Set use ordered linear storage. Pollable stream I/O supports cancellation/deadlines and concurrent close. Uncooperative native code or nonpollable I/O can still delay joining; forced termination does not constitute successful cleanup.

## Commands, builds, and source tools

`ms check`, `build`, `emit`, `run`, `test`, `inspect`, and `diagram` accept a module or project `ms.toml`. Project configuration supports `[project]` and `[aliases]` with strict keys. Standalone modules use their containing directory as the import root. Applications export nongeneric `fn main(process: Process) -> Int`.

### Pins and artifact identity

`ms lock ms.toml` explicitly records compiler/frontend/runtime content and the selected Go toolchain/target in `ms.lock`. Native project builds reject missing or mismatched pins. Check/emit/source inspection do not need pins. Native artifacts have verified cache entries and `<executable>.ms-build.json` with source/configuration and executable hashes. Unchanged outputs are not rewritten. `compiler.VerifyBuild` checks binary/source identity. The compiler generates deterministic source and records artifact identity. Native binaries are not promised to be byte-identical across environments. Parsing and checking still run before an artifact cache hit.

### Generated Go and debug builds

`ms` embeds a compressed build payload and atomically materializes it in the user
cache under its content hash. It contains the Go build driver, compiler, linker,
assembler, assembly headers, the runtime's standard-library dependency closure
for six targets, time-zone data, and licenses. Go tests, documentation, and unrelated
tools are excluded. Pins and native builds share discovery with `GOTOOLCHAIN=local`,
`GOENV=off`, and `CGO_ENABLED=0`, requiring no host Go or C compiler.
`MANUSCRIPT_GO` explicitly overrides tool selection; direct developer binaries
without an embedded payload retain a PATH fallback. `make dist` packages the
single binary, examples, and licenses for Linux, macOS, and Windows on AMD64 and ARM64.

`ms emit` produces one Go file containing its runtime and imports of the pinned vendored dependencies. Native release builds use `-trimpath` using the embedded vendor source bundle without downloading dependencies. Generated source has Go line directives, and programming faults accumulate source function positions. `--debug` disables optimization/inlining while retaining native symbols and absolute source mappings. Debug build cache identities include the source root.

### Formatting and source inspection

`ms fmt file.ms` validates syntax before atomically replacing a file and preserves comments and literal spellings. `--check` reports formatting drift without writing. `ms check --json` emits format-1 diagnostics. `ms inspect` emits checked entities, generated declaration and local names, source hashes, original-byte statement header spans, call sites, and effects. `ms diagram` emits their static Mermaid call graph, including implicit cleanup; neither command represents a runtime trace.

### Editor, lint, debugger, and profiles

`ms lint` reports five advisory hygiene and semantic rules. `ms lsp` supplies typed completion, call snippets, signature help, navigation, project references, checked versioned rename, diagnostics and code actions. Editor-only recovery retains independently valid declarations; strict builds still reject malformed syntax. The [VS Code extension](extensions/vscode/README.md) includes source debugging through Delve and read-only views of records, collections, variants, locals, and execution/service state.

`ms profile` retains CPU/heap profiles, execution traces, executable/build metadata, and source inspection. Runtime work carries source/work/operation labels and cleanup/join trace regions without changing lifetime inheritance. See the [tooling guide](tooling/README.md) for commands and current limits.

### Test execution

`ms test` executes test blocks in the reachable import graph in dependency/source order with `file::name` labels. Each test has a fresh execution lifetime; services join before the next test. Faults fail that test and remaining tests continue. Builds check test bodies but omit their execution code. Duplicate display names are allowed. Tests have no implicit Process authority. Declaration-only fixtures establish parse/check/build acceptance, not behavior of uncalled functions.

## Remaining design work

The book's [outstanding decisions](design/compiler/conformance/scope.md#outstanding-decisions) remain authoritative. The following parts are not implemented:

- External native adapter manifests/ABI, `[adapters]` loading, custom host distributions, and adapter/dependency pins.
- HTTP/3 is excluded by explicit user instruction. Interactive subprocess streams and uniform cross-platform descendant supervision remain separate work.
- Unicode normalization/graphemes/legacy text codecs, seek/watch/permissions APIs, timezone calendars/tickers, archive extraction and specialized formats. See the [coverage map](design/standard-library/packages/coverage.md) for runnable equivalents and remaining gaps.
- Full incremental frontend/package compilation, concrete native generic layouts, precise retained-authority classification, and native adapter effect declarations.
- Transactional structural edits, rich diagnostic spans/related locations, architecture diffs, runtime trace transport, generalized structural value transformations.
- Test discovery globs, identity beyond display labels, authority injection, and expected-fault checks, which need the runner contract finalized.

The language core, supplied standard APIs, compiler commands, and native conformance tests are usable now. The coverage above is not a claim that every future facility in the design book is complete.

## Verification

```sh
go test ./...
go test -race ./runtime ./checker ./compiler ./tooling/...
go vet ./...
go test ./parser -run '^$' -fuzz FuzzParse -fuzztime 10s
go test ./compiler -run '^$' -fuzz FuzzCompile -fuzztime 10s
```

Native end-to-end tests compile accepted syntax and execute test bodies; rejected cases cover typing, visibility, bounds, captures, and service boundaries. Observable tests cover evaluation order, numeric faults, cleanup exits, SIGTERM child-before-parent shutdown, HTTP, subprocesses, source tooling, and unusual module filenames. Runtime tests use barriers/channels for concurrent state transitions; cache tests exercise pin mismatches, corruption, stale sources, and unchanged outputs. CI runs formatting, vet, the complete suite, race tests, and the hello project.
