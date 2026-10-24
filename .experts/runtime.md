# Runtime lessons

The Go runtime (`pkg/runtime`, Go-slice list semantics, Go inlining-budget tuning, host bridges) is deleted. Entries about those internals are gone; what remains are contracts of the standard library and runtime that the Rust runtime (`crates/ms-rt`, `crates/ms-std-*`) must still honor.

### Cancellation is a host-level flag, not a per-loop poll

Decision: the language has no concurrency runtime today (a scoped `TaskGroup` design was approved 2026-10-24, see `proposals/taskgroup.md`; it changes nothing until implemented). Cancellation exists only for signals and shutdown: one global flag checked by runtime calls and I/O, not on loop back edges ([design contract](../crates/DESIGN.md)). A helper that runs in constant time (Optional/Result extraction, builder append) must not check cancellation; keep the check in helpers that loop, wait, or call user callbacks. The cost of the opposite choice was measured on the retired runtime: removing per-call checks from O(1) helpers cut `match` from 7.5 to 6.1 ns/op and `string_append` from 9.2 to 7.1 ns/op. The trade-off is that straight-line code with no loop, such as deep recursion that only unwraps, reaches a cancellation point later.

Apply when: adding a runtime function, or deciding where a function should be a cancellation point.
Evidence: [design contract](../crates/DESIGN.md), [shutdown fixtures](../tests/e2e/testdata/shutdown/server.source), [signal project](../tests/e2e/testdata/projects/signal).
Verify: loop and I/O cancellation cases still stop; compare `bench/perf/programs/run.sh` before and after.

### Runtime guard exits skip native Rust destructors

Verified: production `msrt_guard_call` exits faults and cancellation with a jump, so a Rust
`Drop` guard alone cannot release a response body's active read. Register a runtime cleanup
for state removed across a park; discard it on ordinary return. Interrupted decoders are
closed and abandoned rather than resumed with potentially partial state.

Apply when: native operations take state or resource ownership across a cancellable wait.
Evidence: [response body guard and cancellation regression](../crates/ms-std-net/src/http/client.rs), [runtime guard](../crates/ms-rt/src/fault.rs).
Verify: use the production runtime dependency (not `ms-rt`'s own unwinding unit-test guard),
assert a stack destructor is skipped, join reports cancellation, later reads return Closed,
and the peer observes connection release.

### A native signature change needs the catalogue and a fresh runtime archive

Verified: lowering marshals native calls from `crates/ms-rt/SYMBOLS.md`, not from the Rust source, and programs link `target/ms-native/libms_native.a`. Adding parameters to `msstd_process_command_spawn` without editing its catalogue line made compiled calls pass the out pointer as a mode and segfault inside the native; a stale archive instead ignored the new arguments. Crate tests that call the native directly passed both times. A payload-free alternative parameter crosses as its case index (`p.ty == "i64"`), and a bundled declaration's default such as `Stdio.Pipe` is built by `literal_default`.

Apply when: changing the parameters of any `ms-std-*` or `ms-rt` export.
Evidence: [catalogue](../crates/ms-rt/SYMBOLS.md), [Stdio default](../crates/ms-lower/src/call.rs), [called source check](../tests/e2e/testdata/stdlib/host.ms).
Verify: run `make runtime` and rebuild `ms-cli`, then run a compiled program that calls the native, not only crate tests; `runtime_symbol_catalogue_matches_archive` checks names, not parameters.

### HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.

Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: [called source checks](../tests/e2e/testdata/stdlib/http-headers.ms), [header contracts](../stdlib/http.ms).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered raw-byte acceptance, streaming/client UTF-8 rejection, transport framing validation and domain errors distinct. Do not impose a blanket copy-on-read or membership-copy guarantee; explicit text extraction and copy are distinct operations.

### Concurrency is removed pending a ground-up redesign

Decision: the user removed the concurrency features (TaskGroup, Task, Scheduler, Synchronized, BlockingQueue, `check_cancelled`, `yield_now`, and their lowering, runtime, tooling, tests, examples, and documentation) because concurrency should be rebuilt correctly from the ground up. Do not restore the old APIs or add channels, locks, or tasks without a new user direction. Host-level cancellation (SIGINT/SIGTERM) and `with` cleanup remain. Queue stays a single-threaded FIFO. Older entries or docs that mention Scheduler or timed work predate this removal.

Apply when: a task proposes concurrent work, locks, task handles, or revives the removed APIs.
Evidence: the user's removal request in the "Manuscript agent feedback and experience" project thread; [runtime conventions](../documentation/contributing/runtime-conventions.md).
Verify: no `@std/tasks.ms` or `@std/sync.ms`; `BlockingQueue` is absent from `queue.ms`.

### Newer stdlib direction needs checkout reconciliation

Decision: the stdlib request calls for consolidated grouping and one spelling per operation; optional limits/timeouts honored when supplied; removal of the speculative resource-pooling API; equality and hashing interfaces; and a priority queue. This supersedes the older derived-only equality preference.

Verified: canonical declarations, checker rules, conformance, and generated references implement this direction. Optional also has presence and extraction methods; keep routine absence handling available without requiring a match.

Apply when: changing library signatures, bounds/interfaces, queue APIs, grouping, examples, or documentation.
Evidence: [current declarations](../stdlib/intrinsics.ms); [compiled Optional methods](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: inspect current declarations and called behavior against the latest direction. Preserve omitted/none/explicit-limit behavior and custom equality/hash coherence. Do not restore removed APIs from older documentation or another branch.

### Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [architecture](../documentation/contributing/architecture.md), [networking project](../tests/e2e/testdata/projects/networking), [network fixture](../tests/e2e/testdata/stdlib/net.ms).
Verify: run relevant cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

### Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. The newer simplification lets implementing errors pass directly into Error boundaries and propagate with `try`; the concrete receiver and fields are retained for specific handling.

Decision: keep typed diagnostic information in ordinary domain error fields. The request to simplify error handling supersedes the extra details wrapper introduced earlier. Records and alternative case payloads already support fields of different types; `Result[T, E]` and `try` retain them. Add a cause field only when the domain needs it. Ordinary errors reuse their original runtime value at an Error boundary; local implementations and generic receivers retain scoped dispatch evidence.

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../stdlib/intrinsics.ms); [compiled typed errors](../tests/e2e/testdata/accept/library-errors.ms); [cross-module error dispatch](../tests/e2e/testdata/projects/error_boundaries/conformance_test.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

### Host API names do not establish units or write guarantees

Verified (contracts from the retired runtime; re-check against `stdlib/*.ms` before relying on them): `ProcessControl.monotonic_time` returns nanoseconds since runtime initialization and shares the process uptime origin; host uptime and Clock instants have different origins and domains. FileHandle count-returning writes loop to complete the input, just like Unit-returning native stream writes. A count result does not imply partial success, and failures do not retain a prefix count. The file stream adapter preserves Closed/InvalidInput but translates other filesystem cases to IoError.Failed.

Apply when: documenting host contracts or proposing typed time, flag, stream, or error adapters. Trace validator, conversion, and result code before inferring semantics from names or result shapes; retain explicit migration decisions for public replacements.
Evidence: [host contracts](../stdlib/intrinsics.ms), [process accounting](../stdlib/process.ms), [called host contracts](../tests/e2e/testdata/stdlib/host-contracts.ms).
Verify: bracket raw monotonic readings against elapsed nanoseconds; check multi-chunk byte counts, sequential/positional EOF, shared adapter close and concrete domain errors.

### Native constructor arguments need not be readable fields

Verified: `Bytes(values: List[Int])` has a dedicated constructor rule; declaring `values` as a field did not make native Bytes expose that field. Keep the constructor signature separate from the native `values() -> List[Int]` operation, and keep editor constructor parameters (signature help) separate from receiver declarations. Constructor inputs and extracted lists copy byte values, preserving Bytes immutability.

Apply when: describing native schemas or replacing bogus native fields with operations.
Evidence: [byte declarations](../stdlib/bytes.ms), [called extraction and constructor regressions](../tests/e2e/testdata/stdlib/string-bytes.ms).
Verify: named and positional Bytes construction and direct, stored, and free extraction calls execute; mutating the input or extracted list leaves Bytes unchanged. Editor signature help retains the required values List; generated metadata lists `values` as an operation, with no data field.

### CSV writer defaults can erase a single empty field

Verified: a naive CSV writer emits the same bare line ending for zero fields and one empty field, while a reader skips blank lines. Manuscript must explicitly quote the sole empty field to retain that row, including the quotes in the output budget. Empty rows still serialize as skipped blank lines; changing reader behavior would alter that contract.

Apply when: changing CSV adapters or relying on a codec's round-trip behavior.
Evidence: [called CSV regressions](../tests/e2e/testdata/stdlib/csv.ms), [CSV crate](../crates/ms-std-csv/src), [CSV contract](../stdlib/json.ms).
Verify: round-trip consecutive single empty fields with LF/CRLF and alternate delimiters; check distinct empty-row output and exact byte, row, and cell budgets.

### Native transformations need output implementation evidence

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. `Set.map` and `Map.map_keys` deduplicate output elements/keys, whose module scope can differ from the input element/key scope. Resolve both the receiver scope and the mapped result scope, including explicit specialization and bound methods, and use output evidence for deduplication. Keep Map/Set callback membership snapshots at the native invocation boundary.

Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: [cross-module output evidence](../tests/e2e/testdata/projects/core_parity/conformance_test.ms), [callback mutation conformance](../tests/e2e/testdata/stdlib/core-parity.ms).
Verify: a generic input forwarded from another module still maps to a set deduplicated by the defining output module's equality; two modules can select different implementations for the same type. A bound specialized method retains its defining module, and callback removals or clearing do not alter the traversal's original membership.

### YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator.

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../stdlib/yaml.ms), [called scalar regressions](../tests/e2e/testdata/stdlib/yaml.ms), [YAML contract](../stdlib/json.ms), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization.

### Collection order, failure modes, and stdio cancellation are decided

Decision: Map and Set iterate in insertion order, and keys use the `Hashable` interface with `Equal`. Pick a failure mode by cause: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. Mutators use verbs (`add`, `remove`, `clear`) and return the receiver (the value-semantics migration changes mutator results; see the ownership notes); do not reintroduce removed alias spellings (#358). Blocking stdin/stdout reads are not made cancellable; do not add runtime machinery to interrupt them.

Apply when: adding or renaming collection, standard-library, or I/O members; choosing between Optional, Result, and a fault.
Evidence: [failure-mode rule](../stdlib/intrinsics.ms), [collection order and mutation](../documentation/core-language/types/collections.md), [equality interfaces](../documentation/core-language/types/equality-and-hashing.md), [ownership notes](../crates/ms-check/OWNERSHIP.md).
Verify: iteration after removals and re-adds keeps insertion order for the remaining keys; a new member documents its failure mode and has a doc comment with an example.

### Test plans distinguish declarations from executions

Verified: listing and fail-fast complete a plan with unrun entries; repeat creates separate indexed executions of one declaration. Reader completion must account for skip and intentional unrun outcomes without masking an active incomplete test. `ms test` runs each test in its own process invocation so a fault fails only that test ([design contract](../crates/DESIGN.md)).

Apply when: changing test options, event reporting, or testing helpers.
Evidence: [test runner lowering](../crates/ms-lower/src/runner.rs), [testing lowering](../crates/ms-lower/src/testing.rs), [helper contracts](../stdlib/testing.ms), [testing fixture](../tests/e2e/testdata/stdlib/testing.ms).
Verify: list executes no bodies, fail-fast retains later not_run entries, repeated names retain indices, and fault assertions propagate cancellation and skip.

### Testing helpers do not duplicate test blocks

Decision: the user removed `describe` and `it` callback helpers because wrapping those steps in an existing `test` block duplicates grouping without creating independently selectable or reported cases. Keep assertions directly usable in ordinary test blocks; do not restore these wrappers without a new direction.

Apply when: adding BDD helpers or test suite grouping.
Evidence: the user's explicit removal request; [testing declarations](../stdlib/testing.ms).
Verify: standard testing exports contain assertions, fail and skip, with no callback suite wrappers.

### File fixtures own a separate lifetime from each test

Decision: the user chose an ordinary local `make_fixture()` convention and a concrete return type implementing TestHooks; tests use the implicit fixture binding, while hooks use self. No additional declaration or nesting is required. Omitted hooks are no-ops elaborated only for the canonical standard interface; written hooks retain ordinary signature checking and dispatch.

Verified (design from the retired runtime): file roots retain fixture resources while each test uses independent hosts and work scopes. Listing performs no setup. Unjoined fixture work poisons further use and suppresses owner teardown; closing resources concurrently with that work would race the resource owner. Cooperative cancellation runs teardown with a fresh bounded cleanup context.

Apply when: changing fixture injection, runner hook ordering, or default hooks.
Evidence: [fixture lowering](../crates/ms-lower/src/fixture.rs), [fixture fixture](../tests/e2e/testdata/stdlib/testing-fixture.ms), [testing declarations](../stdlib/testing.ms).
Verify: no setup for `--list`, one construction across repetitions, per-file isolation, ordinary interface calls to omitted hooks, and failure/cancellation cleanup with preserved machine outcomes.

### Typed JSON is generated per type, like format and equality

Decision: the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for JavaScript's `JSON.stringify` behavior: every type is accepted and nothing is rejected at compile time. Two interfaces customize shapes: `JsonEncode.to_json` exists; the `JsonDecode` counterpart is undecided (a record implementing it was proposed because contracts have no static operations). Lowering generates encoder and decoder helpers per concrete type (the `format` pattern) rather than walking a dynamic value model.

Verified: `try` gives its operand no backward context, so write `try parse[T](text)`. A record decode builds the value through the default-argument path, so field defaults run in the record's module with earlier fields in scope; an absent `Optional` field without a default is `none`. Map keys are parsed per key type, and two members that read as one key (`"1"`, `"01"`) are `InvalidData`. Cycle detection tracks only types that can reach themselves. Interface values have no JSON form: a view's concrete type is unknown to the encoder, and giving every view an encoder would pull JSON into every program that uses a contract.

Apply when: adding a standard value type with its own text or number form (extend encoding and decoding together), changing the encoding, or adding typed YAML/TOML encoding.
Evidence: [declarations and guide](../stdlib/json.ms), [JSON lowering](../crates/ms-lower/src/json.rs), [JSON crate](../crates/ms-std-json/src), [native conformance](../tests/e2e/testdata/stdlib/json.ms), [typed codecs](../tests/e2e/testdata/stdlib/typed-codecs.ms).
Verify: a record with a function field and a `none` field encodes without them; `Wrapper[Wrapper[String]]` with a defaulted field decodes; a round trip through `stringify` returns identical text.

### Write operations take String; `_bytes` siblings take Bytes

Decision: write APIs (`write`, `write_file`, `append_file`, `write_at`, on streams, files, connections, transports) accept `String`; raw bytes use a sibling named `<name>_bytes` (`write_bytes`, `write_file_bytes`). Network sends follow the same shape: `DatagramSocket.send`/`send_bytes`, `WebSocket.send`/`send_bytes(data, text: False)`, `ping`/`ping_bytes`, and `request`/`request_bytes` for the body. Interface operations cannot be generic or overloaded, so two names express the choice. Any source `impl` of `WriteStream` or `Transport` must declare both; implementing `write` as `self.write_bytes(data.to_bytes())` keeps one body.

Apply when: adding or changing a write-like standard operation, or implementing `WriteStream`/`Transport` in source.
Evidence: user request in the project thread; [io](../stdlib/io.ms), [fs](../stdlib/fs.ms), [stream support](../tests/e2e/testdata/stdlib/support/streams.ms).
Verify: `stdout().write("text")` and `write_bytes(bytes)` both type-check (`ms check`).

### Collections are constructed from lists, not chained mutation

Decision: `Set[Int]([3, 1, 2])` and `Set([3, 1, 2])` build a Set from a list (insertion order kept, duplicates collapsed); migrate chained `.add` construction in tests and examples. Do not add a second construction spelling (variadic, literal) without a new decision.

Apply when: adding collection constructors or writing fixtures that need a populated Set.
Evidence: [Set declaration](../stdlib/collections.ms), [constructor uses](../tests/e2e/testdata/stdlib/preferred-names.ms), commit c025937b.
Verify: duplicates collapse, first-seen order is kept, and `Set[Int]([])` is empty.

### Forked fault assertions need their own cleanup boundary

Verified: Unix `expect_fault` children inherit the caller's cleanup stack and guard targets.
Running them can delete a still-live parent's external resources or jump to an inherited
callback guard. Clear cleanup records, guards, active fault reports and equality recursion
state in the child before the assertion runs; preserve cancellation, shielding and stack limits.

Apply when: changing fault assertions, fork boundaries or cleanup contexts.
Evidence: [child isolation](../crates/ms-rt/src/trap.rs), [production-runtime regressions](../crates/ms-rt/tests/trap_isolation.rs), [issue #920](https://github.com/manuscript-lang/manuscript/issues/920).
Verify: child faults leave parent cleanup pending, child cleanup runs LIFO, nested assertions
and assertions during fault cleanup retain their own report and cleanup boundaries.

### Task time limits must not depend on the scheduler going idle

Verified: task kill deadlines expired only in `reactor_wait`, which runs when no task is ready.
Two tasks that keep waking each other through a channel never let it run, so a task's timeout
never fired. `switch_away` now expires kills on every switch while any are pending.

Apply when: adding a wake path that makes a task ready without the reactor, or moving deadline checks.
Evidence: [scheduler](../crates/ms-rt/src/task.rs), [channel fixture](../tests/conformance/fixtures/e2e/stdlib/channels.ms) ("a task cancelled before it first ran closes its end").
Verify: a zero-timeout task that only sends on a channel times out instead of running to its end.
