+++
title = "Limits and JavaScript compatibility"
weight = 46
+++

# Limits and JavaScript compatibility

Every public declaration is checked against its native calling signature. The [generated reference](../reference/_index.md) is the contract inventory. Node.js 24 host coverage is tracked separately in [the host guide](node-host.md); an equivalent feature does not imply identical JavaScript coercions or VM behavior.

## Optional limits and deadlines

Limit and timeout parameters use `Optional[T] = none`. Omission or explicit `none` adds no operation budget or deadline. Supply `some(value: ...)` to enforce a budget. Optional limit fields in standard option records may also be omitted; `JsonLimits()` and `ArchiveLimits()` have no imposed budgets.

```manuscript
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import StringError from "@std/string.ms"

fn repeated() -> Result[String, StringError]:
    let unlimited = try "ab".repeat(count: 3)
    return "ab".repeat(count: 3, max_bytes: some(value: 6))
```

Supplied negative bounds are invalid. Zero retains each operation's declared meaning: an output budget allows no output, a zero timeout expires immediately, split's zero limit returns no parts, and a queue's supplied capacity must be positive. Limits are validated even when another limit is omitted.

A chunk read's `max_bytes` requests a chunk size; it does not cap the total stream. Omitted reads use a 64 KiB buffer, and datagrams use their protocol maximum. Signal and file-watcher buffers retain finite default buffer sizes, rather than imposing a total event budget. Protocol restrictions, numeric representability, filesystem authority, and execution cancellation still apply.

Socket reads/writes, datagram send/receive, and listener accept have one operation each with an optional `timeout`. The caller's execution cancellation remains effective with no local timeout. HTTP request/body limits and server admission are likewise optional; omitted server admission does not allocate a fixed-capacity queue.

## Contract audit

| API group | Correspondence and deliberate differences |
| --- | --- |
| Text and collections | Familiar JS operations; Unicode scalar indexing, typed callbacks, mutable collections with explicit shallow cloning, value equality rather than JS object-reference equality |
| Numbers | JS-style floating-point formatting, classification and round-to-positive-infinity ties; checked signed 64-bit Int, Decimal and BigInt are distinct types |
| JSON and codecs | Structured errors, exact JSON number text, strict UTF-8 and invalid-encoding checks; duplicate JSON object keys are rejected |
| Regex | RE2 operations with explicit unsupported JS regex features |
| Filesystem and path | Node host inventory and offline Node path/glob fixtures; explicit source/destination labels, UTF-8 paths, platform errors and scoped handles |
| Process and system | Native command/OS operations; no V8 module loading or JS exception/event hooks |
| Network, TLS, HTTP, WebSocket | Explicit network accessor and native resource interfaces, cancellation and joined cleanup; byte and deadline caps only when supplied |
| Scheduling | One Scheduler for start/after/every and per-ID cancellation/status/restart; ordinary sleep for sequential delay, no Node event-loop phase ordering or ref/unref |
| Queues and synchronization | Local FIFO/stable priority heap plus explicit Synchronized guards; no implicit channel or durable-delivery semantics |

The checker, native ABI integration tests, source fixtures, CLI execution, and documentation freshness checks verify these contracts together. Node-specific behavior remains explicitly identified rather than represented by duplicate API families.
