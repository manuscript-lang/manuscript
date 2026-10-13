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

### Ancestor lock exclusion is broader than actual wait cycles

Verified: Synchronized checks the holder's work lifetime against the acquiring execution's ancestor chain. It rejects ordinary parent/child overlap even when the parent is not joining. Cancellation does not dissolve a cycle involving shielded cleanup, and must not forcibly release a held guard. The bounded tests cover lock-before-join and join-before-lock, task/group joins, group/execution/scheduler shutdown, and cancellation versus release.

Open: permitting safe ancestor contention requires choosing an actual-cycle contract. Checking only when a child acquires misses an ancestor that joins afterward. A detector must coordinate both sides of the dependency and preserve fixed construction ancestry, failed-task group joins, and shielded cleanup. Independent-lock and cross-service cycles are currently invalid application usage; do not silently broaden that contract.

Verified: another operation can close a guard alias while the admitting operation is blocked joining. A wait-for cycle through the admitting lifetime can therefore be broken by independent alias release. A narrower policy must specify whether such potential cycles fault; do not describe them as proof of a permanent deadlock.

Verified: acquisition delivery must use one cancellation observation for both disposal and unwinding. Two final checks can see active then cancelled, discard the result without disposing it, and strand a Synchronized lock. A cancellation arriving after the successful delivery checkpoint belongs to caller cleanup.

Apply when: changing ancestor lock admission, wait-cycle prevention, task/service joins, or acquisition delivery.
Evidence: [issue 148](https://github.com/manuscript-lang/manuscript/issues/148), [synchronization contract](../documentation/concurrency/synchronization.md), [bounded regressions](../pkg/runtime/synchronized_ancestor_test.go), [acquisition delivery](../pkg/runtime/values.go), and [undelivered acquisition regression](../pkg/runtime/synchronized_test.go).
Verify: run the Synchronized and TaskGroup tests repeatedly and with the race detector. Any permissive contract must change the overlapping contention case to wait and return 7 while retaining bounded cycle/cleanup rejection in both orders.

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
Evidence: [extractor](../pkg/compiler/toolchain_cache.go), [interrupted archive and concurrent publication tests](../pkg/compiler/toolchain_test.go).
Verify: truncated archives fail, leave no published/staging cache, and permit a complete retry; concurrent valid callers reuse one immutable result.

### Native option adapters must respect declared parameter types

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

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. Set.map deduplicates output elements, whose scope can differ from the input element's scope. Lower both the receiver scope and the mapped result scope, including explicit specialization and bound methods; use output evidence for deduplication. Keep callback membership snapshots at the native invocation boundary and payload references shallow.

Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: [receiver lowering](../pkg/compiler/lower_collections.go), [native dispatch](../pkg/runtime/collections.go), [cross-module output evidence](../tests/e2e/testdata/projects/core_parity/main.ms), and [callback mutation conformance](../tests/e2e/testdata/stdlib/core-parity.ms).
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
