+++
title = "Common package contracts"
weight = 48
+++

# Common package contracts

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

These pages document executable additions to the Go compiler/runtime. Types and signatures are defined in the pinned Manuscript sources under `stdlib/`; the checker reads those declarations and verifies native runtime ABI signatures against them. Types are individually imported from their named module. Standard imports remain pinned with the distribution; there are no ambient new types, wildcard imports, user-defined generic operations, or implicit external authority.

Each function identity includes its module (`json/parse`, `bigint/parse`, `url/parse`), avoiding same-name binding collisions in generated code. Source import aliases remain unsupported: use a helper module when two exports have the same spelling. Sequential callbacks may suspend and are invoked under the caller's context; sharing proofs are required only by the existing concurrent APIs, not by sequential collection helpers.

## Errors

`@std/errors.ms` exports LibraryError with nullary cases InvalidInput, InvalidData, OutOfRange, LimitExceeded, NotFound, AlreadyExists, PermissionDenied, Unsupported, Closed, Timeout, AuthenticationFailed and case Failed(message: String). This small common error alternative keeps new package operations composable with ordinary Result/try. Existing IoError, CommandError and task errors keep their identities and contracts. Error messages are diagnostic, not stable classification codes.

Malformed data and unavailable OS services return Result errors. Absence uses Optional. Illegal collection slice bounds, inconsistent programmer assumptions, and assertion failures fault. Parent cancellation unwinds and never becomes EOF/domain error; local network deadline failure returns Timeout. Networking supports verified TLS, DNS records, Unix sockets, streaming HTTP and WebSockets; HTTP/3 is explicitly excluded by user instruction. Native builds bundle pinned dependency sources/licenses and never fetch packages.

Native acquisition disposes an undelivered successful resource when cancellation wins before return. Acquired socket handles use with and share synchronized close admission; retained aliases cannot extend open lifetime.

## Bounds and native limits

Caller-supplied nonnegative byte/item/depth bounds reject excess rather than truncating success. Pure functions over an already-created String/List/Bytes do not bound the caller's preexisting allocation. Go parsers may allocate one CSV record or ZIP central directory before an item bound can be checked; log serialization creates a record before its byte check. Bound source reads for untrusted inputs, and consult each package's limits. JSON has depth ceiling 512, HTTP has 64 KiB response headers, entropy has 16 MiB per call, and UDP receives at most 65535 bytes. This is not a universal heap/CPU sandbox.

Native loops check cancellation between bounded chunks. Individual Go math, regex matching, big-integer operations, directory operations, resolver calls and OS operations can delay cancellation until the native call returns. No forced termination is introduced. Write/copy/remove failures may leave external partial effects; no implicit rollback or transaction is promised.

## Authority

CLI Process adds filesystem, entropy, wall_clock and system roots; existing network and commands roots are extended/reused. Source fakes implement these contracts using normal explicit shared views. Pure codecs/path/math/hash functions grant no OS authority. The native CLI roots use the process's OS permissions: filesystem subtree restrictions are not implemented; Network.restrict enforces scoped destination policy. Imports never manufacture authority. New HTTP/socket operations retain TLS verification and use explicit authority values.
