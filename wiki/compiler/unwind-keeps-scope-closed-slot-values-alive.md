[Wiki](../index.md) › [Compiler and build](index.md)

# Unwind keeps scope-closed slot values alive

Verified: inlining a mutable method can turn a `take` from a caller parameter into a `take` from a local slot. The slot still contains the same physical value while that value is only borrowed. If a scope close owns the slot, registering a second unwind drop frees the receiver before the older close uses it. A wrapper around `ReadStream` exposed this as a Release crash on task timeout or a guarded read fault.

Coverage must be active, not inferred from a cleanup registration somewhere in the function. After the scope entry is discarded, normal close can still fault: a borrowed caller slot then needs its own unwind drop. Leaving that slot permanently classified as covered leaks its interface allocation in Debug.

Prove identity through every incoming block argument and actual cleanup-handle lifetime. Mixed fresh values, slot overwrites, escaping addresses or borrowed projections, and unproven consumers cannot inherit another value's cleanup coverage. Track pointer projections through proven borrowing calls rather than treating them as independent values. Preserve the independent drop after coverage ends.

Borrow proofs follow resources and addresses, not numeric results: consuming or returning a position record containing only integers cannot escape its decoder. Keep raw pointers tracked, including pointers nested in otherwise non-dropping records, alternatives and optionals. Updating a non-dropping record field preserves its owned resources only when that field does not control ownership. In particular, `SharedGuard.held` decides whether its payload is dropped or copied; the unwind proof and backend use the same guard-field recognition.

A slot may be mutated locally before its scope close is discarded. Distinguish a nonescaping parameter that immediately puts an updated record back from one that preserves every owned resource. Only the latter permits a snapshot across its call. Break snapshot windows at mutations and load fresh contents afterward; reject missing or conditional write-back, pointer escapes and stale takes put back after a forwarded mutator. The branch-sensitive discard proof remains necessary.

Apply when: changing inlining, mutable-slot lowering, unwind ownership classification, or cleanup handle tracking.
Evidence: [production lifecycle regressions](../../tests/e2e/testdata/accept/close-interface-unwind.ms), [zero-live-block gate](../../tests/ownership-counts/close_interface_unwind.ms), [MIR coverage controls](../../crates/ms-mir/tests/unwind.rs), [unwind pass](../../crates/ms-mir/src/unwind.rs).
Verify: execute the lifecycle fixture in Debug and Release, including conditional reads, reverse close order, guarded read faults and faults during normal close; run the ownership count gate so successful close assertions cannot hide leaks.

Also run [mutable-slot ownership counts](../../tests/ownership-counts/slot_borrow_unwind.ms). A glibc counting runtime needs both `ms-native/entry` and `ms-rt/stats`, as built by `tools/lib.ms`. Check a trivial program reports zero live blocks before comparing leaks. An archive without process entry can fail before the lifecycle case starts; that is invalid setup evidence, not a cleanup regression.
