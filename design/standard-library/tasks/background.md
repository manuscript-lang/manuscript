+++
title = "Background services"
weight = 37
+++

# Background services

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `Background` for work managed by an application or component rather than by the caller's immediate request. Import it from `@std/tasks.ms`. The service tracks its operations and implements `Closeable` so shutdown can wait for them.

You can create several services and pass them as ordinary parameters. The [API reference](../types/prelude.md#background-service) defines which callables they accept.

```manuscript
with emails = Background(limit: 32):
    with indexing = Background(limit: 4):
        serve(emails: emails, indexing: indexing)
```

The constructing host supplies the execution parent. Construct application services under the application lifetime, session services under the session lifetime, and request services under the request lifetime. Calling a service from another context never reparents it.

## Starting work

```manuscript
import Result from "@std/result.ms"
import map_error from "@std/result.ms"
import Background from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"

type MailError:
    case Rejected

interface Mailer:
    fn send(to: String) -> Result[Unit, MailError]

fn enqueue(emails: Background, mailer: Mailer & Shareable, address: String) -> Result[OperationId, StartError]:
    let send = fn() -> Result[Unit, String]:
        return map_error(
            result: mailer.send(to: address),
            transform: fn(cause: MailError) -> String:
                return "Email delivery failed"
        )
    return emails.start(operation: send)
```

Start does not wait for capacity. Accepting work, reserving a slot, and checking closure happen atomically. The `limit` counts accepted operations whose completion has not yet been committed. Accepted work starts without an extra unbounded queue; rejected work never runs.

Completion frees the slot before failure reporting, so a slow reporter cannot hold up new admission. Start does not retry automatically.

Background operations return `Result[Unit, String]`: explicit `ok(value: unit)` on success, or a String error after domain-error adaptation. Successful operations produce status; failures reach the reporter. One operation's failure does not cancel unrelated operations.

The returned `OperationId` is the same identity used in execution errors, failure reports, and traces. With this service, it supports status and cancellation without transferring shutdown responsibility. The [standard API contract](../types/prelude.md#background-service) defines signatures, status retention, constructor defaults, bounded reporting, and fallback diagnostics.

Closures retain ordinary captured references. Capture a request-data snapshot and application services, then acquire resources inside the operation's own `with` blocks. Capturing a request's resource does not extend its lifetime; use after close returns a resource-specific error. Closure syntax is the ordinary syntax in [function values and closures](../../core-language/functions/function-values-and-closures.md).

Bind the operation's data in an ordinary closure; there is no function-plus-arguments submission form.

## Lifetime and shutdown

Pass `Background` directly. Its `start` binding follows the [direct-call restriction](../types/prelude.md#direct-calls-only). Sharing or dropping a service reference or work ID does not change its lifetime or cancel work. Work never transfers between services.

`close() -> Unit` is idempotent and does not finish until admitted work and its cleanup have ended:

1. Close admission atomically across all aliases.
2. Allow a configured drain period; the default is no drain delay.
3. Request cancellation of unfinished operations.
4. Join every admitted operation and finish bounded reporting/cleanup.

Cancelling a submitting request does not cancel accepted work. Cancelling the service's fixed parent does cancel its operations, even if a drain period was configured. A service's close cannot join itself; host/component code outside its operations performs shutdown.

Hosts choose overall budgets, admission/reporting settings, and an escalation policy for uncooperative work. Expiry is not successful joining; the runtime cannot forcibly terminate an arbitrary goroutine safely. Closing a service before closing its application dependencies is required.

This is process-local execution, not durable delivery. Work that must survive restart needs a durable queue. If acknowledgement can be lost during request cancellation, use application idempotency keys to make resubmission safe.

## Runtime and library responsibilities

The Go runtime supplies operation start, stop, join, and synchronization. Admission, reporting, and shutdown policy can be implemented over those primitives. The initial implementation may provide the service in Go behind the same imported API. These native primitives are implementation details, not source intrinsics. The compiler validates the standard binding's callable proofs; service admission, status retention, reporting, drain, cancellation, and joining remain library/runtime behavior.
