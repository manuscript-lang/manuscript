# Bounded task-channel lifetime tracking

## Summary

- Result collection currently removes the only channel reference visited by group close (#1457).
- Track live group-end channel leases without retaining them from the group.
- Each lease owns its lane-closing callback and removes itself when its last channel handle drops.
- Cost: one small native lease per live channel and one tracker per group; no compiler or ownership-rule changes.

## Status

- Implemented, 2026-10-26, based on main `7003f9fad5b33f2fa7c53cb3a0469929857dd0c5`.
- User decision, 2026-10-26 16:45:50 UTC: "yes group close should close every channel that’s handed by that group".
- This resolves #1457 while preserving #1218's bounded collection requirement.
- Independent skeptical review approved the revised design before implementation, requiring deferred-drop, reentry and last-holder regressions. The original node-retention step was rejected because deferred drops reuse the count word.
- Verification: baseline source fixture failed 9/12 cases; rebuilt runtime passes all 12 in Debug and Release. Native runtime tests pass 131/131, including five new lease lifecycle regressions.
- Rebased onto main `2e1227ae36f3b3b20a421c12a6522b95f076e37a`: workspace fmt/clippy, native131/131 and rebuilt-source12/12 Debug/Release pass again. The original base also passed1038 workspace tests, full conformance2292/2292 and307 Release e2e fixtures.

## Problem

- Verified in `stdlib/tasks.ms`: `Task.result` removes its `Entry`; `TaskGroup.close` only closes remaining entries.
- Buffered and empty collected channels therefore receive values/EOF after group close instead of `ChannelError.Closed`.
- A closed flag alone cannot promptly release unread values; retaining every collected channel restores #1218.

## Design

- Add internal native `TaskChannels` and `TaskChannelLease` handles to `stdlib/tasks.ms`, using the existing reference-counted extern-type ABI. `TaskChannels` is exported because a public `TaskGroup` field cannot expose a private type; it has no public operations. The lease remains private.
- A group owns its tracker; each group-end transport retains a lease that owns a zero-argument closure calling existing `close_end(down, up)`.
- The tracker contains an intrusive list of weak lease pointers. A lease strongly retains its tracker and unlinks before destruction; the tracker never retains leases or callbacks.
- Collecting results still removes task entries. Dropping the last group-end handle immediately releases its lease, callback and otherwise unreferenced lane values.
- After cancelling/joining tasks, group close retains the tracker, marks it closed, detaches each lease and takes its callback, closes its group end and drops the callback.
- Closed trackers immediately close newly created leases, covering spawn after close. Repeated close is inert.
- Callbacks use existing lane locks/clear/wake logic. They run after task cleanup, so buffered task output remains drainable before group close and is released at close.
- Never access or retain a detached lease after taking its callback: clearing messages may destroy it, and `Obj::drop_slow` can defer a zero-count object's destructor while reusing its count as a pending link. The callback's moved ownership remains valid independently of the node.
- Intrusive links avoid a high-water-mark array or history of dead channels. Tracker storage is constant plus live lease nodes; no values/waiters survive through tracking alone.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt/src/channel.rs` | Private tracker/lease handles and three native entry points | Unlink, callback/drop, reentry and bounded-live-node tests |
| `ms-rt/SYMBOLS.md` | Register the entry-point ABI | Catalogue/source execution |
| `stdlib/tasks.ms` | Carry leases on group ends; close tracker after scope retirement | Collected, uncollected, empty, buffered, cloned and late channels |
| `documentation/core-language/concurrency/task-groups.md` | Clarify collected-channel lifetime | Existing and new source assertions |
| Tests and runtime expert guidance | Pin the contract and its bounded implementation | Debug/Release, allocation probes, full checks |
| Parser/checker/lowering/MIR/codegen, `ms-rt-abi`, other groups | Unchanged | Existing conformance |

## Alternatives

- Do nothing: contradicts the user's resolved close-all contract.
- A group-closed flag in channel operations: rejects use but retains unread buffers until handles drop.
- Keep every collected channel strongly: unbounded retention from #1218 returns.
- Prune strong references during spawn: dead channels and values remain retained while the group is idle.
- Generic weak references or changes to object headers/drop glue: much broader than this resource-lifetime repair.
- Put the weak list directly in runtime `Scope`: removes one native handle type but couples late channel destruction to scope-slot reuse and scheduler teardown; a retained tracker gives the weak list its own simple lifetime.
- Source-only close callbacks stored by the group: callbacks strongly capture lanes and retain dead channels; source has no drop hook to unlink them.

## Staging and verification

- First prove source regressions fail on main; add native lifecycle tests before relying on weak pointers.
- Verify callbacks/drop happen exactly once, last-handle drop unlinks while the group stays open, reentry and deferred drops are safe, and late leases close immediately.
- Verify unread payload allocation releases at group close with a retained handle and long-lived collect/drop loops stay bounded.
- Run workspace fmt/clippy/nextest/docs, conformance, e2e and declaration docs checks. Publish draft, require exact-head CI, then merge and validate containing main.

## Open questions

- No remaining semantic question: the user explicitly chose close-all behavior. Review is about the smallest safe implementation.
