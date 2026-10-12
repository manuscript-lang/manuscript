# Runtime lessons

### Sharing, resource lifetime, and work lifetime are separate

Decision: the canonical design separates safe concurrent access from keeping a resource open and from joining work. A captured reference does not extend a `with` lifetime. Callable sharing proofs have their own boundary rules; a safe capture is not a declaration of intended authority.

Apply when: changing closures, parallel work, background services, resource wrappers, or pools.
Evidence: [sharing](../design/ownership-and-cleanup/values/sharing.md); [joined groups](../design/concurrency/joining.md); [scope-exit ordering](../design/ownership-and-cleanup/cleanup/exit-order.md). These establish the design contract, not a claim that every runtime path has been tested.
Verify: exercise use after close and shutdown with work still running. Confirm started work completes cleanup before joining returns and stale resource aliases cannot reach a reused handle.

### Networking completeness includes interruption and shutdown

Decision: the networking request explicitly required finishing networking rather than deferring gaps, with HTTP/3 excluded for that task. Public signatures alone did not meet the requested scope; cancellation, close, bounded streaming, and shutdown were part of the behavior.

Apply when: adding native network APIs or declaring a networking change complete.
Evidence: [scope corrections in Solidify networking implementation](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [network coverage and limits](../IMPLEMENTATION.md#standard-library-and-runtime); [network regression cases](../runtime/networking_test.go).
Verify: run relevant native and compiled cases for blocked I/O cancellation, concurrent close, bounded input/output, and shutdown joining. Check the actual request's protocol scope; retain implementation limits explicitly when a path remains uncooperative.

### Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. A generic boundary uses an explicit view or `map_error` with `as_error`; it retains the concrete receiver so contract type patterns can select a specific error. Convenience through `try` is not a reason to erase error identity or an underlying cause.

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../design/standard-library/packages/contracts.md#errors); [native identity and stream-cause regressions](../runtime/library_test.go); [compiled matching and mapping](../tests/e2e/testdata/accept/library-errors.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

### Keep concurrency collection helpers removed

Decision: the dedicated concurrent collection-mapping API was removed because the user considers it redundant. Do not restore that helper under another name without a new user direction. Fixed-operation parallel work and Background retain their existing contracts.

Apply when: adding concurrent collection utilities or revising the task API.
Evidence: [task declarations](../stdlib/tasks.ms); [concurrency guide](../design/concurrency/_index.md); the user's removal request in this chat.
Verify: inspect source declarations, native bindings, compiler handling, examples, and generated references together; removing an export alone leaves an incomplete removal.
