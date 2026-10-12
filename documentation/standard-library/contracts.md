+++
title = "Errors and limits"
weight = 3
+++

# Errors and limits

These rules apply across the standard library. Exact types and signatures live in the pinned Manuscript files under `pkg/stdlib/`. The checker reads those files and verifies that native runtime signatures agree with them.

## Imports and callbacks

Import each function or type you name from its module. Standard imports are pinned with the distribution. They add no ambient types, wildcard imports, user-defined generic operations, or automatic imports of host accessors.

Function identity includes the module, so `json/parse`, `bigint/parse`, and `url/parse` remain distinct in generated code. Source import renaming is unsupported; use a helper module if two imports have the same spelling.

Sequential callbacks run under the caller's execution context and may wait for operations. All callbacks are ordinary values and can also be passed to concurrent APIs.

## Errors

An error is an ordinary value returned in `Result[T, E]`. Standard packages define errors for their own domain, such as `JsonError` and `IoError`; their cases and fields appear in the [generated reference](reference/_index.md). Match the result to handle an error, or use `try` to return it unchanged to a compatible error boundary.

### Error details

Put typed information directly in an error record or alternative case. Each field has its own type. A domain error does not need an `Error` implementation to be returned or propagated.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Result from "@std/result.ms"
import panic from "@std/faults.ms"

type ReadError:
    path: String
    attempt: Int
    retryable: Bool

fn failed_read() -> Result[Unit, ReadError]:
    return error(cause: ReadError(path: "settings.json", attempt: 2, retryable: true))

test "read typed error fields":
    match failed_read():
        ok(_):
            return panic(message: "failed read succeeded")
        error(cause):
            if cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable:
                return panic(message: "missing error details")
```

Records and their fields retain ordinary mutable value semantics. Add a cause field when an error needs to preserve another failure; its type can be that specific domain error.

### Several error types at one boundary

Use `Error` from `@std/errors.ms` when a boundary should handle several error types through one `message() -> String` operation. Standard errors implement this interface; custom errors can declare an ordinary `impl Error` in their defining module.

Pass or return a specific error directly where `Error` is expected. Functions returning `Result[T, Error]` can use `try` with specific standard errors, or forward a `Result[T, SpecificError]` with the same success type. The original error and its fields are retained. Call `message()` for a diagnostic, or use a [contract type match](../core-language/control-flow/pattern-matching.md#contract-type-patterns) to recover the concrete error. See [common error boundaries](../core-language/errors/results.md#a-common-error-boundary) for an example.

Unrelated domain errors still need an explicit translation. The Error interface does not constrain Result's error parameter or turn faults and cancellation into expected failures.

| Situation | Behavior |
| --- | --- |
| Malformed data or unavailable OS service | Return an expected Result error. |
| Missing value | Use Optional. |
| Illegal collection slice bounds, broken programming assumptions, or explicit invariant violation | Produce a programming fault. |
| Parent cancellation | Unwind; do not turn cancellation into EOF or a domain error. |
| Local network deadline expires | Return Timeout, subject to the operation's documented error type. |

If cancellation wins before a newly acquired resource is delivered, native acquisition releases that resource. Delivered socket handles use `with` and synchronized close admission. Retaining another reference never extends the open lifetime.

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

## Bounds and native limits

Byte, item, and depth limits are optional; omission adds no operation cap. Supplied limits are nonnegative unless a package requires a positive value. Budget exhaustion returns an error; split limits intentionally truncate the returned parts.

A limit on a function's output does not bound input already allocated by the caller. Some native operations also allocate before they can check a limit: CSV may parse one record, ZIP may read the central directory, and logging may construct a full record. Bound source reads and consult each package's behavior section.

| Facility | Native limit |
| --- | --- |
| JSON | Supplied depth budgets are respected; cycles cannot be serialized. |
| HTTP | Header limits are optional; the native reader remains constrained by integer representability. |
| Entropy | 16 MiB per call. |
| UDP receive | At most 65535 bytes. |

These limits do not form a general memory or CPU sandbox.

## Cancellation and partial effects

Native loops check cancellation between bounded chunks. A single math, regex, big-integer, directory, resolver, or OS call may delay cancellation until it returns. There is no forced termination.

Writing, copying, or removing data can fail after changing an external prefix. Cancellation and errors do not imply rollback or a transaction.

## Access to external services

Imported host accessors supply filesystem, entropy, wall-clock, system, network, and command services. Source fakes implement the same contracts with explicit contract views.

Pure codec, path, math, and hash functions grant no OS access. Native CLI services use the process's OS permissions. Filesystem subtree restrictions are not implemented; `Network.restrict` narrows destination access. Imported host accessors obtain services from the current execution. HTTP and socket operations retain their service interfaces and TLS verification.

Networking includes DNS, Unix sockets, verified TLS, streaming HTTP, and WebSockets. HTTP/3 is outside the supported scope. Native builds bundle pinned dependency sources and licenses rather than fetching packages.
