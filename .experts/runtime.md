# Runtime lessons

### HTTP field folding must not erase map entries

Verified: source Map keys use exact equality, while HTTP field names fold ASCII case. Passing case-equivalent outgoing entries through `Header.Set` silently replaces earlier values, including separate `Set-Cookie` fields. Append in source insertion order after validating all fields. `Header.Values(key)` also canonicalizes lookup: when converting an existing host map, index its exact key to avoid substituting another spelling's values.

Apply when: changing HTTP adapters, repeated fields, or header representation bridges.
Evidence: [header regressions](../pkg/runtime/library_http_header_transport_test.go), [called source checks](../tests/e2e/testdata/stdlib/http-headers.ms), and [header contracts](../documentation/standard-library/http.md#header-lookup-and-repeated-values).
Verify: both insertion orders retain every duplicate/cookie; host maps with noncanonical keys lose no values. Keep buffered byte input, streaming text input, exact Map lookup, and existing domain errors distinct. Public representation unification needs a separate migration decision.

### Empty cleanup omission needs callable ownership evidence

Verified: lexical cleanup lists return to empty after lowering a `with` scope;
their final length cannot prove that a callable needs no stack. Track whether
lowering emitted a registration owned by that source callable. Default expressions
and generated match closures share its stack; nested source functions/closures
save independent state. With no registration, `Unwind` only recovers and rethrows,
so omitting it preserves the surrounding source tracing, return/propagation and
cancellation wrappers.

Apply when: changing generated cleanup setup or adding lowering scopes.
Evidence: [callable lowering](../pkg/lower/lower_functions.go),
[ownership tests](../pkg/lower/lower_scalar_test.go),
[native cancellation/fault checks](../pkg/build/lower_scalar_native_test.go),
and [runtime unwind](../pkg/runtime/tasks.go).
Verify: conditional/default/match registrations retain stacks; a nested source
closure does not force an unused parent stack; return, propagation, fault and
cancellation retain cleanup and frame behavior.

### Synchronized uses cancellable cross-task blocking

Decision: the user approved ordinary cross-task blocking for issue 148 after reviewing the automatic cycle detector's measured task overhead. Same-operation reentry faults using execution/work-lifetime identity, including helper and shielded views. Different executions, including descendants, wait. The reviewed graph draft and measurements remain in [superseded PR 256](https://github.com/manuscript-lang/manuscript/pull/256); that proposal was not merged and must not be silently restored.

Verified: cancellation stops ordinary lock waits, but it neither forcibly releases an executing holder nor abandons joined cleanup. Shielded cleanup ignores initiating cancellation and expired deadlines, so a cross-task cleanup cycle may remain blocked. Native RunMain has no cleanup watchdog or second-signal escalation. Do not claim universal deadlock detection or guaranteed timeout escape. Preserve task/group/service self-join guards and release held guards before joining dependent work.

Verified: another operation can close a guard alias while its owner is blocked joining. Access/release remains atomic, stale aliases cannot reach a later acquisition, and close stays idempotent. Work lifetime, resource lifetime and sharing remain separate.

Verified: acquisition delivery uses one final cancellation observation for both disposal and unwind. Two checks can discard an acquired guard without disposing it. Keep PR 230's disposal fix; later cancellation after successful delivery belongs to caller cleanup.

Apply when: changing lock admission, cancellation, alias release, task/service joining or acquisition delivery.
Evidence: [issue 148](https://github.com/manuscript-lang/manuscript/issues/148), [user decision](codex://threads/01a12c8b-2b5a-71ad-8446-e786ea4580df), [contract](../documentation/concurrency/synchronization.md), [bounded blocking regressions](../pkg/runtime/synchronized_ancestor_test.go), and [acquisition delivery](../pkg/runtime/values.go).
Verify: ordinary ancestor overlap returns 7; both lock/join orders block until cooperative cancellation or release. Exercise deadlines, same-operation helper/shield reentry, cancellation/delivery/release races, alias close and use after close. Shielded-cycle tests run in bounded disposable subprocesses and release aliases explicitly; no test relies on cleanup timeout escape.

### Attribute profiling at execution boundaries

Verified: allocating pprof labels, derived executions, and trace regions for every source call can dominate a call-heavy program and create enormous traces. Source boundaries follow immutable context inheritance; task/scheduler work explicitly starts a new boundary. Nested calls keep source mapping in CPU sample stacks while reusing the boundary context. CPU labels and trace tasks/regions must follow their independently requested collectors; heap-only capture needs neither.

Verified: attribution runs on the same execution and goroutine. Preserve the full execution state when changing its context; the work-inheritance helper can intentionally start new call accounting. Resetting that state for source labels changes admission at the depth limit and fault-frame bookkeeping. The profiling depth-limit regression distinguishes these cases.

Apply when: changing source-call wrappers, profiling, work-context inheritance, or capture defaults.
Evidence: [profiling implementation](../pkg/runtime/profile.go), [boundary/allocation and repeated-run regressions](../pkg/runtime/profile_test.go), [native exit/flush checks](../pkg/build/profile_test.go), and [profiling contract](../documentation/developer-tooling/implementation.md#debugging-and-profiling).
Verify: measure unprofiled execution separately from capture setup/flush; repeat CPU/heap/trace modes. Preserve cancellation/lifetime and caller-label restoration, including faults. Validate all requested outputs with bundled viewers and keep default artifact changes explicit in help, docs, and manifest tests.

### Newer stdlib direction needs checkout reconciliation

Decision: the stdlib request calls for Node.js/JavaScript contract parity with consolidated grouping and one spelling per operation; optional limits/timeouts honored when supplied; removal of the speculative resource-pooling API; equality and hashing interfaces; and a priority queue. This supersedes the older derived-only equality preference. The combined scheduling service is `Scheduler`, with one lifecycle for immediate and timed work.

Verified: canonical declarations, runtime dispatch, checker rules, conformance, and generated references now implement this direction. Optional also has presence and extraction methods; keep routine absence handling available without requiring a match.

Apply when: changing library signatures, bounds/interfaces, queue APIs, scheduling, grouping, examples, or documentation.
Evidence: [the user request](codex://threads/01a13126-1245-730b-9e5d-16ca2dc7501f); [current declarations](../pkg/stdlib/README.md); [stdlib contract](../documentation/standard-library/contracts.md); [runtime regressions](../pkg/runtime/stdlib_revamp_test.go); [compiled Optional methods](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: inspect current declarations and called behavior against the latest direction. Preserve omitted/none/explicit-limit behavior, custom equality/hash coherence, and joined Scheduler shutdown. Do not restore removed APIs from older documentation or another branch.

### Sharing, resource lifetime, and work lifetime are separate

Decision: the canonical design separates safe concurrent access from keeping a resource open and from joining work. A captured reference does not extend a `with` lifetime. All values may be shared without callable proofs. Native services synchronize their internals. The user subsequently chose a single-threaded Queue with an optional capacity parameter; shared queue access uses Synchronized guards, including reads. Passing references is permitted without implying internal thread safety. A safe capture is not a declaration of intended authority.

Apply when: changing closures, task-group work, schedulers, resource wrappers, or owned resources.
Evidence: [sharing](../documentation/concurrency/sharing.md); [joined groups](../documentation/concurrency/joining.md); [scope-exit ordering](../documentation/core-language/cleanup/exit-order.md). These establish the design contract, not a claim that every runtime path has been tested.
Verify: exercise use after close and shutdown with work still running. Confirm started work completes cleanup before joining returns and stale resource aliases cannot reach a reused handle.

Verified: SIGINT/SIGTERM observation does not claim the signal; native host cancellation races independently with `SignalStream.next()`. Registered cleanup is shielded, but shielding a close call does not revive workers derived from the cancelled construction parent. Join workers before draining application-owned pending data directly in close while its dependencies remain open. See the [shutdown cookbook](../documentation/concurrency/shutdown.md), [disposable-child signal tests](../tests/e2e/shutdown_cookbook_test.go), and [already-cancelled worker test](../pkg/runtime/shutdown_test.go). The current native host has no cleanup watchdog; do not infer implemented escalation from the contributor policy.

Verified: a queued transport operation can acquire a ready gate even when its lifetime cancellation is also ready. An asynchronous cancellation callback does not guarantee the operation's derived context is cancelled before stream dispatch. Recheck the closed state after acquiring the gate; otherwise queued writes can reach the stream after shutdown starts. See [transport admission](../pkg/runtime/library_log.go) and `TestLogCloseInterruptsActiveAndQueuedWrites` in [logging regressions](../pkg/runtime/library_log_test.go). Repeat the close/caller-cancellation cases under the race detector when changing this path.

### Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [scope corrections in Solidify networking implementation](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [network coverage and limits](../documentation/contributing/architecture.md#standard-library-and-runtime); [network regression cases](../pkg/runtime/networking_test.go).
Verify: run relevant native and compiled cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

### Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. The newer simplification lets implementing errors pass directly into Error boundaries and propagate with `try`; the concrete receiver and fields are retained for specific handling.

Decision: keep typed diagnostic information in ordinary domain error fields. The request to simplify error handling supersedes the extra details wrapper introduced earlier in this chat. Records and alternative case payloads already support fields of different types; `Result[T, E]` and `try` retain them. Add a cause field only when the domain needs it. Ordinary errors reuse their original runtime value at an Error boundary; local implementations and generic receivers retain scoped dispatch evidence. See [error details](../documentation/standard-library/contracts.md#error-details), [compiled typed errors](../tests/e2e/testdata/accept/library-errors.ms), and [cross-module error dispatch](../tests/e2e/testdata/projects/error_boundaries/main.ms).

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../documentation/standard-library/contracts.md#errors); [native identity and stream-cause regressions](../pkg/runtime/library_test.go); [compiled matching and mapping](../tests/e2e/testdata/accept/library-errors.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

### Host API names do not establish units or write guarantees

Verified: ProcessControl.monotonic_time returns time.Since(runtime initialization) as nanoseconds and shares the process uptime origin; host uptime and Clock instants have different origins/domains. FileHandle count-returning writes loop to complete the input, just like Unit-returning native stream writes. A count result does not imply partial success, and failures do not retain a prefix count. The file stream adapter preserves Closed/InvalidInput but translates other filesystem cases to IoError.Failed.

Apply when: documenting host contracts or proposing typed time, flag, stream, or error adapters. Trace validator/conversion/result code before inferring semantics from names or result shapes; retain explicit migration decisions for public replacements.
Evidence: [host contracts](../documentation/standard-library/contracts.md#native-io-success-and-eof), [process accounting](../documentation/standard-library/process.md#process-time-and-accounting), [nanosecond bracketing](../pkg/runtime/library_host_contract_test.go), and [called host contracts](../tests/e2e/testdata/stdlib/host-contracts.ms).
Verify: bracket raw monotonic readings against elapsed nanoseconds; check multi-chunk byte counts, sequential/positional EOF, shared adapter close and concrete domain errors in compiled tests.

### Native constructor arguments need not be readable fields

Verified: `Bytes(values: List[Int])` has a dedicated constructor rule; declaring `values` as a field did not make native Bytes expose that field. Removing the bogus field without preserving `ConstructorSignature` also loses editor constructor parameters. Checking and editor queries now share that constructor signature separately from the native `values() -> List[Int]` operation, which uses the existing free function's implementation. Constructor inputs and extracted lists copy byte values, preserving Bytes immutability.

Apply when: describing native schemas or replacing bogus native fields with operations. Preserve dedicated constructor arguments separately from receiver declarations and bindings.
Evidence: [constructor signatures](../pkg/checker/types.go), [constructor checking](../pkg/checker/calls.go), [byte declarations](../pkg/stdlib/bytes.ms), [native receiver identities](../internal/nativeabi/receivers.go), [editor signature regressions](../pkg/tooling/lsp/features_test.go), and [called extraction and constructor regressions](../tests/e2e/testdata/stdlib/string-bytes.ms).
Verify: named and positional Bytes construction and direct, stored, and free extraction calls execute; mutating the input or extracted list leaves Bytes unchanged. Editor signature help retains the required values List; generated metadata must list `values` as an operation, with no data field.

### Keep concurrency collection helpers removed

Decision: the dedicated concurrent collection-mapping API was removed because the user considers it redundant. Do not restore that helper under another name without a new user direction. Scoped TaskGroup work and Scheduler retain separate lifecycle contracts.

Apply when: adding concurrent collection utilities or revising the task API.
Evidence: [task declarations](../pkg/stdlib/tasks.ms); [concurrency guide](../documentation/concurrency/_index.md); the user's removal request in this chat.
Verify: inspect source declarations, native bindings, compiler handling, examples, and generated references together; removing an export alone leaves an incomplete removal.

### Local queues compose with explicit synchronization

Decision: keep Queue a local FIFO, unbounded when capacity is omitted and bounded when a positive capacity is supplied; use Synchronized when sharing it between concurrent operations. Full and empty results return immediately. Queue has no mutex, waiting, close, or cleanup lifecycle. Wrapping it does not add channel wakeups, and every alias must use the same wrapper's lock.

Apply when: changing queue APIs, examples, sharing claims, or native collection implementations.
Evidence: [queue contract](../documentation/concurrency/queues.md); [FIFO and synchronized-sharing tests](../pkg/runtime/queue_test.go); [source conformance](../tests/e2e/testdata/accept/queues.ms); the user's Queue simplification and capacity correction.
Verify: construction without capacity grows as needed; explicit zero or negative capacity faults. Bounded full enqueue returns false without changing contents, empty reads return none, draining permits reuse, and shared access under one wrapper passes race checks. Do not restore implicit synchronization or blocking channel semantics.

### Borrowing file descriptors must preserve pollable I/O

Verified: `os.File.Fd()` can switch a pollable descriptor into blocking mode. Native metadata and sync helpers that use it can make later cancellation fail even though ordinary file tests pass. The host bridge borrows descriptors with `SyscallConn.Control` instead, preserving the runtime's deadline/cancellation behavior.

Apply when: implementing native descriptor operations alongside cancellable file or stream adapters.
Evidence: [native descriptor bridge](../internal/hostos/hostos.go), [metadata and file operations](../pkg/runtime/library_fs.go), and [pipe cancellation regression](../pkg/runtime/library_host_parity_test.go).
Verify: `TestExpandedHandleCancellationAndStreamAdapters` and runtime race checks, including cancellation after descriptor metadata access and closure through a shared adapter.

### One scheduler owns immediate and timed work

Decision: the stdlib revamp merges the work service and scheduled timers into `Scheduler`, with one ID/status/cancel/restart/report/close lifecycle. Time retains sequential sleep and clock values. Admission/history caps are optional, as are native operation budgets/deadlines. Explicit zero must not be confused with omission.

Apply when: changing scheduling, native adapters, optional limits, or Node/JS coverage mappings.
Evidence: [task declarations](../pkg/stdlib/tasks.ms), [limit contract](../documentation/standard-library/contracts.md), [runtime cases](../pkg/runtime/stdlib_revamp_test.go), and [native host mappings](../documentation/standard-library/filesystem.md#timers-and-scheduling).
Verify: omit a cap and admit more work; supplied caps still reject excess. Restart returns a fresh ID after joining the old operation, and parent shutdown joins callback cleanup. Check native optional arguments in legacy host adapters as well as LibraryMethods.

### Validate compression completion before publishing tools

Verified: tar EOF can precede the gzip trailer. A complete tar payload with a truncated trailer must not become a ready toolchain. Extraction now drains the compressed reader before publication, validating truncation and checksum; retries retain no partial cache.

Apply when: changing SDK extraction or cache publication.
Evidence: [extractor](../pkg/build/toolchain_cache.go), [interrupted archive and concurrent publication tests](../pkg/build/toolchain_test.go).
Verify: truncated archives fail, leave no published/staging cache, and permit a complete retry; concurrent valid callers reuse one immutable result.

### Native option adapters must respect declared parameter types

Verified: a required Int delegated to an Optional[Int] operation needs the
explicit Some representation when preserving its public negative-limit fault.
The optional adapter rejects negative payloads inside Some; a raw negative Int
can reach a distinct primitive fault instead. String.replace_n deliberately
adapts its required cap before calling replace's prepared body. Evidence:
[negative diagnostic/frame parity](../tests/e2e/replace_n_test.go) and
[required-cap adapter](../pkg/runtime/library_data.go).
Verify zero/positive caps, negative empty/nonempty/direct/bound calls, required
source arity and declared ABI shape together; preserving the raw algorithm alone
does not preserve preparation semantics.

Verified: normalizing every runtime record recognized as an options record corrupts generic payloads. An Optional fallback containing JsonLimits must retain Optional fields and shared storage; it is not a limits argument to an I/O adapter. Normalize only a concrete declared parameter matching the record identity, including a concrete Optional parameter after its outer wrapper is removed.

Apply when: changing native argument normalization or generic receiver methods.
Evidence: [normalization boundary](../pkg/runtime/library_options.go), [runtime Optional regression](../pkg/runtime/optional_test.go), and [compiled record fallback](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: unwrap_or returns a JsonLimits record with negative and absent Optional fields unchanged and mutations retain its identity; concrete limits passed to their native operations remain validated.

### CSV writer defaults can erase a single empty field

Verified: Go's CSV writer emits the same bare line ending for zero fields and one empty field, while its reader skips blank lines. Manuscript must explicitly quote the sole empty field to retain that row, including the quotes in the output budget. Empty rows still serialize as skipped blank lines; changing reader behavior would alter that contract.

Apply when: changing CSV adapters or relying on a host codec's round-trip behavior.
Evidence: [CSV implementation](../pkg/runtime/library_formats.go), [called CSV regressions](../tests/e2e/testdata/stdlib/csv.ms), and [CSV contract](../documentation/standard-library/formats.md#csv-behavior).
Verify: round-trip consecutive single empty fields with LF/CRLF and alternate delimiters; check distinct empty-row output and exact byte, row, and cell budgets.

### Native transformations need output implementation evidence

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. Set.map and Map.map_keys deduplicate output elements/keys, whose scope can differ from the input element/key scope. Lower both the receiver scope and the mapped result scope, including explicit specialization and bound methods; use output evidence for deduplication. Keep Map/Set callback membership snapshots at the native invocation boundary and payload references shallow.

Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: [receiver lowering](../pkg/lower/lower_collections.go), [native dispatch](../pkg/runtime/collections.go), [cross-module output evidence](../tests/e2e/testdata/projects/core_parity/main.ms), and [callback mutation conformance](../tests/e2e/testdata/stdlib/core-parity.ms).
Verify: a generic input forwarded from another module still maps to a set deduplicated by the defining output module's equality; two modules can select different implementations for the same type. A bound specialized method retains its defining module, and callback removals or clearing do not alter the traversal's original membership.

### Typed task handles replace heterogeneous aggregation

Decision: the user chose TaskGroup and Task[T] over the compiler-only heterogeneous aggregation binding because ordinary generic declarations are simpler to reason about and expose usable source signatures to tooling. Group join returns Result[Unit, ExecutionError]; each task join preserves its own T. Remove the old binding and its pack machinery rather than adding a compatibility alias.

Apply when: changing joined work, standard task declarations, result inference, or editor signatures.
Evidence: the user's direction in this implementation chat; [task declarations](../pkg/stdlib/tasks.ms); [task group contract](../documentation/concurrency/task-groups.md); [joining](../documentation/concurrency/joining.md).
Verify: native heterogeneous-handle and cached-result fixtures, cancellation/close races, self-join rejection, ordinary source navigation/signatures, and generated reference freshness.

### YAML folding must retain physical blank lines until decoding

Verified: stripping continuation lines before joining loses paragraph breaks and can misclassify comment markers inside an open quote. Quoted and plain folding remove the first break before empty lines; folded blocks do so only between ordinary lines, preserving breaks around more-indented content. Chomping also needs to know whether the final physical line had a terminator.

Apply when: changing YAML scalar gathering, comment removal, whitespace handling, folding, or chomping.
Evidence: [YAML parser](../pkg/stdlib/yaml.ms), [called scalar regressions](../tests/e2e/testdata/stdlib/yaml.ms), [YAML contract](../documentation/standard-library/formats.md#yaml-behavior), and [YAML 1.2 folding](https://yaml.org/spec/1.2.2/#65-line-folding).
Verify: run all five issue examples plus escaped continuations, whitespace-only blank lines, more-indented blocks, all chomping modes, and missing final terminators under LF/CRLF/CR normalization.

### List traversal follows the captured Go slice header

Decision: the user's later instruction explicitly supersedes List membership
snapshot/COW guarantees. Capture the slice and initial length once, expose writes
to shared backing elements, and never extend a traversal on append. Reallocation
leaves the running traversal on its original array. No traversal-driven List copy
or hidden shared flag is needed. Map/Set snapshots, closure variable capture,
explicit shallow clone/slice storage and synchronization contracts remain distinct.

Decision: shrinking boxed List mutations use non-clearing Go copy/append and
reslice semantics. Vacated cells keep prior valid values; captured ranges can
observe shifted/repeated tails. Full splice-to-empty shortens the header, preserving
backing capacity; an explicit header reset releases that receiver's backing.
Removed references can remain retained until overwritten/reallocated/released.

Verified: nil clearing in the earlier draft caused an unframed Int conversion
panic. A `[]Value` nil oracle and a native loop ignoring its binding both missed
typed-consumption safety. Parent approved non-clearing behavior without implicit
copies or invented zero values. Evidence: [typed Go oracles](../pkg/runtime/list_shrink_test.go),
[called consumers](../tests/e2e/testdata/accept/list-shrink-consumers.ms),
[original reproducer now succeeding](../scripts/bench-lists/repro-cleared-tail.ms),
and [fix/retention review](../scripts/bench-lists/go-range-review.md#non-clearing-shrink).

Apply when: changing List traversal, callbacks, writers or typed numeric storage.
Evidence: [range/mutation oracle](../pkg/runtime/list_range_test.go),
[called native Go-range cases](../tests/e2e/testdata/accept/list-go-range.ms),
[loop contract](../documentation/core-language/control-flow/loops.md#iterable-types-and-binding),
and [measured no-copy follow-on](../scripts/bench-lists/go-range-review.md).
Verify: capture once, mutate in place, append with/without growth, shrink, reverse
and self-splice; observed reads match ordinary Go backing-array behavior. Explicit
clones stay separate and append-only callbacks visit only the initial length.
Also consume yielded values after shrink in called native/standalone regressions,
checking types, source fault frames, cancellation, explicit clone independence,
and retained memory after clearing/reusing/releasing backing capacity.

Verified: a mutating predicate can shift/replace the current List cell. `find`
and `find_last` must capture the element before invoking the predicate and return
that same shallow value when it matches; index variants return the captured index.
Reloading the cell afterward returned an element the predicate never matched.
Body-versus-dispatch comparisons share the bug, so use independent expected values
and Go operation oracles. Evidence: [search regression](../pkg/runtime/list_find_mutation_test.go)
and [called search/view/alias consumers](../tests/e2e/testdata/accept/list-shrink-consumers.ms).

Verified: List equality must capture both outer headers before checking lengths
and invoking element Equal. Reloading live length/cells let user Equal skip a
mismatch after left shrink, panic after right shrink, extend membership on append,
or switch arrays after reallocation. Capture retains visible backing writes and
shallow payload references; eager cloning would also change the contract.
Evidence: [independent equality mutation oracle](../pkg/runtime/list_equality_mutation_test.go)
and [native/standalone user Equal consumers](../tests/e2e/testdata/accept/list-equality-mutation.ms).
Verify both operands under shrink, append with spare capacity, forced growth and
replacement of later cells, including callback counts and differing tail values.

Verified: primitive storage keeps the mutable slice header on the authoritative
`*List`, with two allocations for fresh nonempty backing. A captured `ListRange`
is a traversal header, not another mutable owner. `Items` is only legacy boxed
construction; typed consumers use storage-aware methods. Dynamic Optional reads
still allocate at the value boundary, so benchmark the compiler's typed access
and comparator consumers together with storage. Typed comparator constructors
accept raw bodies and install exactly one guarded admission; passing an already
guarded body doubles accounting. Evidence: [storage migration](../documentation/contributing/list-storage.md),
[primitive Go oracles and allocation/guard tests](../pkg/runtime/list_storage_test.go),
and [measured storage/access paths](../scripts/bench-lists/typed-storage.md).
Verify: fresh constructors and effectful sized initialization use two allocations,
typed at/unwrap uses none, generic forwarding retains identity, and comparator
profiling/returns/cancellation/depth/fault frames match ordinary source calls.

Verified: primitive sized initializers must use direct matching typed writes
after fresh-state/kind/bounds checks. Routing known typed construction through
generic Len/Set made each initializer non-inlineable (Go 1.25.1 cost 118); the
strict checks inline at cost 31 and preserve two construction allocations.
Evidence: [strict initialization safety/allocation tests](../pkg/runtime/list_initialization_test.go),
[approved runtime mitigation](https://github.com/manuscript-lang/manuscript/pull/315#issuecomment-6157742485).
Verify actual effectful generated literals as well as this runtime control;
inlining alone does not establish construction performance parity.

Decision: the approved borrowed argument ABI is restricted to generated bodies
that copy parameter Values and cannot retain/expose their incoming slice.
`NewCompiledSourceFunction` delegates the ordinary source guard once; `for_each`
reuses one buffer per invocation only for exact labels and this proof. Recursion
must have independent buffers, unmarked callbacks may retain fresh arrays, and
adapters conservatively drop the marker. Individual Value captures retain identity.
Evidence: [approved contract](https://github.com/manuscript-lang/manuscript/pull/315#issuecomment-6157745861),
[retention/reentry/checkpoint/guard/allocation tests](../pkg/runtime/borrowed_arguments_test.go).
Verify actual emitted ordinary callbacks against the prior boxed baseline; a
runtime marked-body control does not establish compiler proof or payload parity.
