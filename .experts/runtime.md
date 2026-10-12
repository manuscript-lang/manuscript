# Runtime lessons

### Sharing, resource lifetime, and work lifetime are separate

Decision: the canonical design separates safe concurrent access from keeping a resource open and from joining work. A captured reference does not extend a `with` lifetime. All values may be shared without callable proofs. Native services synchronize their internals. The user subsequently chose a single-threaded Queue with an optional capacity parameter; shared queue access uses Synchronized guards, including reads. Passing references is permitted without implying internal thread safety. A safe capture is not a declaration of intended authority.

Apply when: changing closures, parallel work, background services, resource wrappers, or pools.
Evidence: [sharing](../documentation/ownership-and-cleanup/values/sharing.md); [joined groups](../documentation/concurrency/joining.md); [scope-exit ordering](../documentation/ownership-and-cleanup/cleanup/exit-order.md). These establish the design contract, not a claim that every runtime path has been tested.
Verify: exercise use after close and shutdown with work still running. Confirm started work completes cleanup before joining returns and stale resource aliases cannot reach a reused handle.

### Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [scope corrections in Solidify networking implementation](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [network coverage and limits](../documentation/implementation.md#standard-library-and-runtime); [network regression cases](../runtime/networking_test.go).
Verify: run relevant native and compiled cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

### Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. A generic boundary uses an explicit Result match and an Error view; it retains the concrete receiver so contract type patterns can select a specific error. Convenience through `try` is not a reason to erase error identity or an underlying cause.

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../documentation/standard-library/packages/contracts.md#errors); [native identity and stream-cause regressions](../runtime/library_test.go); [compiled matching and mapping](../tests/e2e/testdata/accept/library-errors.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

### Keep concurrency collection helpers removed

Decision: the dedicated concurrent collection-mapping API was removed because the user considers it redundant. Do not restore that helper under another name without a new user direction. Fixed-operation parallel work and Background retain their existing contracts.

Apply when: adding concurrent collection utilities or revising the task API.
Evidence: [task declarations](../stdlib/tasks.ms); [concurrency guide](../documentation/concurrency/_index.md); the user's removal request in this chat.
Verify: inspect source declarations, native bindings, compiler handling, examples, and generated references together; removing an export alone leaves an incomplete removal.

### Local queues compose with explicit synchronization

Decision: keep Queue a local FIFO, unbounded when capacity is omitted and bounded when a positive capacity is supplied; use Synchronized when sharing it between concurrent operations. Full and empty results return immediately. Queue has no mutex, waiting, close, or cleanup lifecycle. Wrapping it does not add channel wakeups, and every alias must use the same wrapper's lock.

Apply when: changing queue APIs, examples, sharing claims, or native collection implementations.
Evidence: [queue contract](../documentation/standard-library/data-and-io/queues.md); [FIFO and synchronized-sharing tests](../runtime/queue_test.go); [source conformance](../tests/e2e/testdata/accept/queues.ms); the user's Queue simplification and capacity correction.
Verify: construction without capacity grows as needed; explicit zero or negative capacity faults. Bounded full enqueue returns false without changing contents, empty reads return none, draining permits reuse, and shared access under one wrapper passes race checks. Do not restore implicit synchronization or blocking channel semantics.

### Borrowing file descriptors must preserve pollable I/O

Verified: `os.File.Fd()` can switch a pollable descriptor into blocking mode. Native metadata and sync helpers that use it can make later cancellation fail even though ordinary file tests pass. The host bridge borrows descriptors with `SyscallConn.Control` instead, preserving the runtime's deadline/cancellation behavior.

Apply when: implementing native descriptor operations alongside cancellable file or stream adapters.
Evidence: [native descriptor bridge](../internal/hostos/hostos.go), [metadata and file operations](../runtime/library_fs.go), and [pipe cancellation regression](../runtime/library_host_parity_test.go).
Verify: `TestExpandedHandleCancellationAndStreamAdapters` and runtime race checks, including cancellation after descriptor metadata access and closure through a shared adapter.

### Host parity preserves Manuscript's scheduling model

Decision: when reviewing the Node host expansion, the user asked to simplify timers because they should feel native to Manuscript, not be a blind copy. Use the existing time module and ordinary execution model: sequential `sleep`, concurrent `after`/`every`, one scoped `Timer`, and task-level yielding. Do not duplicate callback/Promise timer families or introduce separate waitable and scheduled handles merely to match Node export names.

Apply when: adding scheduling APIs or using another runtime's API inventory as a completeness target.
Evidence: the user's timer simplification correction; [time declarations](../stdlib/time.ms), [native host mappings](../documentation/standard-library/packages/node-host.md#timers-and-scheduling), and [scheduling conformance](../runtime/library_host_parity_test.go).
Verify: ordinary callbacks remain first-class values, cancellation and close join admitted work, and the inventory maps compositions without restoring duplicate public APIs.
