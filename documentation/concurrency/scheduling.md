+++
title = "Scheduling work"
weight = 4
+++

# Scheduling work

`Scheduler` from `@std/tasks.ms` manages immediate, delayed, and repeating work under one fixed lifetime. Ordinary sequential delays use `sleep` from `@std/time.ms`.

```manuscript
import Scheduler from "@std/tasks.ms"
import Result from "@std/result.ms"

fn send() -> Result[Unit, String]:
    return ok(value: unit)

fn start_work() -> Unit:
    with scheduler = Scheduler():
        let immediate = scheduler.start(send)
        let delayed = scheduler.after(duration: 20.milliseconds, operation: send)
        let repeated = scheduler.every(interval: 1.seconds, operation: send)
```

The three admission operations return `Result[OperationId, StartError]`. They share `status(id)`, `cancel(id)`, failure reporting, and scoped shutdown. `after` accepts a nonnegative delay; `every` requires a positive interval. Invalid durations return `InvalidInput`. A repeating callback runs sequentially and waits its interval after each completion; missed intervals do not accumulate callbacks. A returned failure stops repetition and reaches the reporter.

`Scheduler()` has no admission or status-history cap. Supply `limit: n` to bound accepted unfinished operations, or `history_limit: n` to retain only the most recent completed statuses. A supplied admission limit must be positive; history may be zero. Optional `reporter` and `drain` use Optional callback and Duration values. Their defaults are the host diagnostic sink and immediate cancellation on close. Omitted caps and explicit `none` mean unbounded.

Admission checks closure and reserves capacity atomically. Full admission returns `Full` immediately and does not run the operation; completion releases capacity before reporting. A supplied admission limit also bounds pending reports, with overflow sent to host diagnostics. With no limit, reports queue without an imposed cap. Reporter calls run serially outside transition locks; shutdown joins them.

`restart(id)` cancels and joins an active scheduled operation, then starts its original schedule with a fresh ID. It also restarts completed or failed schedules while their history is retained. Immediate-operation IDs and unknown or evicted IDs return `InvalidInput`; closed services return `Closed`. Restarting from the service's own callback or reporter faults because it could join itself. Keep the returned new ID for subsequent status or cancellation.

## Lifetime and shutdown

Construct a scheduler under the application, component, session, or request lifetime that should own its work. Submitting from another execution does not reparent accepted work. Captured resources must remain usable for the entire operation; references do not extend a resource's `with` lifetime.

`cancel(id)` requests cancellation without joining. Unknown IDs are harmless no-ops. `status(id)` returns `Unknown` for IDs the scheduler did not admit or has evicted. IDs are never reused. Dropping an ID or alias has no effect on work lifetime.

`close()` stops admission, allows the optional drain period, cancels unfinished work, and joins callbacks, their cleanup, and reporting. It is idempotent across aliases. Parent cancellation also cancels accepted work. A callback or reporter cannot close its own scheduler. Close the scheduler before its dependencies.

Scheduling is process-local. Work that must survive a process restart needs durable application storage. Shutdown cannot forcibly terminate uncooperative native code; host escalation is described in [runtime requirements](../contributing/concurrent-runtime.md).
