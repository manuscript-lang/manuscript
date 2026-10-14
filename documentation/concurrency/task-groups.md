+++
title = "Starting tasks"
weight = 1
+++

# Starting tasks

Use a `TaskGroup` to start independent operations and retrieve each result through a typed `Task[T]` handle. Ordinary calls remain sequential; `start` explicitly starts concurrent work.

## Starting and joining tasks

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import { TaskGroup, ExecutionError } from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn number() -> Int: 42
fn greeting() -> String: "hello"

fn check() -> Result[Unit, ExecutionError]:
    with tasks = TaskGroup():
        let number_task = tasks.start(number)
        let greeting_task = tasks.start(greeting)
        let completed = try tasks.join()
        let value = try number_task.join()
        let message = try greeting_task.join()
        if value != 42 or message != "hello":
            return panic("task results changed")
        return ok(unit)

test "independent typed results":
    match check():
        ok(_):
            return
        error(_):
            return panic("task group failed")
```

`start` infers `T` from its zero-argument callback. The handles above have types `Task[Int]` and `Task[String]`. Naming `Task` in an annotation requires its own import; inferred handles do not. Handles can be stored in records, passed through generic functions, returned, and collected in ordinary homogeneous lists.

`Task.join()` waits for that task's body and cleanup, returning `Result[T, ExecutionError]`. Successful individual joins leave admission open. Repeated joins return the cached outcome without running the callback again. Successfully committed values remain available after the group closes.

`TaskGroup.join()` seals admission and waits for every submitted task and its cleanup, returning `Result[Unit, ExecutionError]`. Repeated group joins are permitted. Starting new work after a group join or close is a programming fault. To retrieve values after joining the group, join each retained handle; those reads are immediate.

## Preparation

Each `start` evaluates its receiver and callback argument before submitting that operation. Creating a closure snapshots its captures without running its body. Once a `start` succeeds, its operation may run while the caller prepares later submissions. If later preparation fails, the enclosing `with` cancels and joins previously started work.

Passing `load_user()` executes that call during preparation. Pass a function such as `load_user` or an explicitly typed zero-argument closure instead. Function values, bound methods, and contract views retain their ordinary rules; saving generic `start` as a function value requires explicit specialization, such as `tasks.start[Int]`.

Concurrent effect order is nondeterministic. Shared mutable data needs explicit synchronization; see [Synchronized](synchronization.md#synchronized). Capturing a Map, List, or record shares its storage. See the [unsafe and guarded capture examples](sharing.md#captured-mutable-data) and the limits of the MSL105 advisory before mutating captured data.

## Errors and scope exit

A callback's return value is preserved unchanged. If it returns `Result[User, UserError]`, its handle is `Task[Result[User, UserError]]` and joining returns `Result[Result[User, UserError], ExecutionError]`. A domain error is ordinary completion and does not cancel siblings. Handle execution and domain errors separately; `try` requires the enclosing function's exact error type.

A task fault cancels siblings. A failed task join or group join waits for their cleanup before reporting `ExecutionError.Crashed`. Successfully committed task values remain available independently of a later sibling fault. See [joined group outcomes](joining.md#group-lifecycle).

Use `with tasks = TaskGroup()` to give the work a lexical lifetime. Scope exit calls `close()`, which cancels unfinished tasks and joins them. Closing is idempotent through aliases. A task cancelled by explicit close has an `ExecutionError.Cancelled` outcome. An unobserved task programming fault surfaces from close; joining the failure explicitly marks it observed.

References do not extend work or resource lifetimes. A saved task handle can read a completed result after its group closes, but cannot keep unfinished work running. Resource cleanup remains explicit through `with`; results and captures are not recursively closed.

## Timeouts

`TaskGroup(timeout: 2.seconds)` applies one budget starting at the first submission. Omitted or `none` timeout adds no limit; inherited cancellation still applies. Negative timeouts fault. A zero timeout starts no callback and yields `Timeout`; an empty group joins successfully. Timeout expiry cancels unfinished work and joins it before reporting failure.

A group's task or descendant must not join or close that same group, or join one of its handles. These operations fault before waiting to prevent self-joining. See [joining](joining.md), [cancellation](cancellation.md), and [runtime contracts](../contributing/concurrent-runtime.md).
