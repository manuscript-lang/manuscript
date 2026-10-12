+++
title = "Common package contracts"
weight = 48
+++

# Common package contracts

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Package index](_index.md)

These rules apply across the general-purpose packages. Exact types and signatures live in the pinned Manuscript files under `stdlib/`. The checker reads those files and verifies that native runtime signatures agree with them.

## Imports and callbacks

Import each function or type you name from its module. Standard imports are pinned with the distribution. They add no ambient types, wildcard imports, user-defined generic operations, or automatic access to external services.

Function identity includes the module, so `json/parse`, `bigint/parse`, and `url/parse` remain distinct in generated code. Source import renaming is unsupported; use a helper module if two imports have the same spelling.

Sequential callbacks run under the caller's execution context and may wait for operations. All callbacks are ordinary values and can also be passed to concurrent APIs.

## Errors

Import `LibraryError` from `@std/errors.ms`. It has these cases:

```manuscript
type LibraryError:
    case InvalidInput
    case InvalidData
    case OutOfRange
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case AuthenticationFailed
    case Failed(message: String)
```

This shared error type lets package operations compose through ordinary `Result` and `try`. Existing `IoError`, `CommandError`, and task errors keep their own identities. Use error cases for classification; message text is diagnostic and is not a stable code.

| Situation | Behavior |
| --- | --- |
| Malformed data or unavailable OS service | Return an expected Result error. |
| Missing value | Use Optional. |
| Illegal collection slice bounds, broken programming assumptions, or explicit invariant violation | Produce a programming fault. |
| Parent cancellation | Unwind; do not turn cancellation into EOF or a domain error. |
| Local network deadline expires | Return Timeout, subject to the operation's documented error type. |

If cancellation wins before a newly acquired resource is delivered, native acquisition releases that resource. Delivered socket handles use `with` and synchronized close admission. Retaining another reference never extends the open lifetime.

## Bounds and native limits

Byte, item, and depth limits are nonnegative unless a package requires a positive value. Exceeding a bound returns an error, not a truncated success.

A limit on a function's output does not bound input already allocated by the caller. Some native operations also allocate before they can check a limit: CSV may parse one record, ZIP may read the central directory, and logging may construct a full record. Bound source reads and consult each package's behavior section.

| Facility | Native limit |
| --- | --- |
| JSON | Depth ceiling of 512. |
| HTTP | Response headers limited to 64 KiB. |
| Entropy | 16 MiB per call. |
| UDP receive | At most 65535 bytes. |

These limits do not form a general memory or CPU sandbox.

## Cancellation and partial effects

Native loops check cancellation between bounded chunks. A single math, regex, big-integer, directory, resolver, or OS call may delay cancellation until it returns. There is no forced termination.

Writing, copying, or removing data can fail after changing an external prefix. Cancellation and errors do not imply rollback or a transaction.

## Access to external services

CLI Process supplies filesystem, entropy, wall_clock, and system roots, alongside network and commands. Source fakes implement the same contracts with explicit contract views.

Pure codec, path, math, and hash functions grant no OS access. Native CLI services use the process's OS permissions. Filesystem subtree restrictions are not implemented; `Network.restrict` narrows destination access. Imports alone grant no authority. HTTP and socket operations use explicit service values and retain TLS verification.

Networking includes DNS, Unix sockets, verified TLS, streaming HTTP, and WebSockets. HTTP/3 is outside the supported scope. Native builds bundle pinned dependency sources and licenses rather than fetching packages.
