+++
title = "Common package contracts"
weight = 48
+++

# Common package contracts

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Package index](_index.md)

These rules apply across the general-purpose packages. Exact types and signatures live in the pinned Manuscript files under `pkg/stdlib/`. The checker reads those files and verifies that native runtime signatures agree with them.

## Imports and callbacks

Import each function or type you name from its module. Standard imports are pinned with the distribution. They add no ambient types, wildcard imports, user-defined generic operations, or automatic imports of host accessors.

Function identity includes the module, so `json/parse`, `bigint/parse`, and `url/parse` remain distinct in generated code. Source import renaming is unsupported; use a helper module if two imports have the same spelling.

Sequential callbacks run under the caller's execution context and may wait for operations. All callbacks are ordinary values and can also be passed to concurrent APIs.

## Errors

Each package returns a named error type from its own module: `JsonError` from `@std/json.ms`, `EncodingError` from `@std/encoding.ms`, `FileSystemError` from `@std/fs.ms`, and so on. Each type contains the cases relevant to that domain; its exact definition is in the [generated reference](../reference/_index.md). For example, `JsonError` has only `InvalidInput`, `InvalidData`, and `LimitExceeded`.

All standard error types explicitly implement `Error` from `@std/errors.ms`, an ordinary operation contract with `message() -> String`. Specific API signatures retain their domain error type. A generic boundary uses `Result[T, Error]`; use an ordinary Result match and return `error(cause: Error(value: cause))`. The explicit view preserves the original receiver, case, and payload. See the [executable filesystem/random/time example](https://github.com/manuscript-lang/manuscript/blob/main/tests/e2e/testdata/projects/library/main.ms).

Handle a concrete error with its ordinary case match. Handle a generic `Error` by calling `message()`, or use a [contract type match](../../core-language/control-flow/pattern-matching.md#contract-type-patterns) to recover a concrete error such as `JsonError(cause)`, then match its cases. The final wildcard handles other implementations. Custom errors participate through an ordinary `impl Error for CustomError` in their defining module. `Error` does not constrain `Result`'s error parameter or turn faults and cancellation into expected failures.

`try` propagates the declared error type; it does not convert unrelated types or implicitly construct an Error view. This replaces the former shared `LibraryError` contract: update imports and return annotations, and qualify cases such as `JsonError.InvalidData` when multiple imported types define the same case name.


| Situation | Behavior |
| --- | --- |
| Malformed data or unavailable OS service | Return an expected Result error. |
| Missing value | Use Optional. |
| Illegal collection slice bounds, broken programming assumptions, or explicit invariant violation | Produce a programming fault. |
| Parent cancellation | Unwind; do not turn cancellation into EOF or a domain error. |
| Local network deadline expires | Return Timeout, subject to the operation's documented error type. |

If cancellation wins before a newly acquired resource is delivered, native acquisition releases that resource. Delivered socket handles use `with` and synchronized close admission. Retaining another reference never extends the open lifetime.

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
