# Runtime lessons

### Empty cleanup omission needs callable ownership evidence

Verified: lexical cleanup lists return to empty after lowering a `with` scope;
their final length cannot prove that a callable needs no stack. Track whether
lowering emitted a registration owned by that source callable. Default expressions
and generated match closures share its stack; nested source functions/closures
save independent state. With no registration, `Unwind` only recovers and rethrows,
so omitting it preserves the surrounding source tracing, return/propagation and
cancellation wrappers.

Apply when: changing generated cleanup setup or adding lowering scopes.
Evidence: [callable lowering](../pkg/compiler/lower_functions.go),
[ownership tests](../pkg/compiler/lower_scalar_test.go),
[native cancellation/fault checks](../pkg/compiler/lower_scalar_native_test.go),
and [runtime unwind](../pkg/runtime/tasks.go).
Verify: conditional/default/match registrations retain stacks; a nested source
closure does not force an unused parent stack; return, propagation, fault and
cancellation retain cleanup and frame behavior.

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
Evidence: [extractor](../pkg/compiler/toolchain_cache.go), [interrupted archive and concurrent publication tests](../pkg/compiler/toolchain_test.go).
Verify: truncated archives fail, leave no published/staging cache, and permit a complete retry; concurrent valid callers reuse one immutable result.

### Native option adapters must respect declared parameter types

Verified: normalizing every runtime record recognized as an options record corrupts generic payloads. An Optional fallback containing JsonLimits must retain Optional fields and shared storage; it is not a limits argument to an I/O adapter. Normalize only a concrete declared parameter matching the record identity, including a concrete Optional parameter after its outer wrapper is removed.

Apply when: changing native argument normalization or generic receiver methods.
Evidence: [normalization boundary](../pkg/runtime/library_options.go), [runtime Optional regression](../pkg/runtime/optional_test.go), and [compiled record fallback](../tests/e2e/testdata/accept/optional-methods.ms).
Verify: unwrap_or returns a JsonLimits record with negative and absent Optional fields unchanged and mutations retain its identity; concrete limits passed to their native operations remain validated.

### Typed task handles replace heterogeneous aggregation

Decision: the user chose TaskGroup and Task[T] over the compiler-only heterogeneous aggregation binding because ordinary generic declarations are simpler to reason about and expose usable source signatures to tooling. Group join returns Result[Unit, ExecutionError]; each task join preserves its own T. Remove the old binding and its pack machinery rather than adding a compatibility alias.

Apply when: changing joined work, standard task declarations, result inference, or editor signatures.
Evidence: the user's direction in this implementation chat; [task declarations](../pkg/stdlib/tasks.ms); [task group contract](../documentation/concurrency/task-groups.md); [joining](../documentation/concurrency/joining.md).
Verify: native heterogeneous-handle and cached-result fixtures, cancellation/close races, self-join rejection, ordinary source navigation/signatures, and generated reference freshness.
