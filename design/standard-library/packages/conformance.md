+++
title = "Expanded library conformance"
weight = 61
+++

# Expanded library conformance

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

These executable checks exercise package behavior through the compiler and native runtime. Use the listed fixtures and tests to verify data handling, limits, errors, and cleanup.

- `tests/e2e/testdata/accept/library*.ms`: compiler-to-native execution for exact JSON numbers, duplicate-key/depth failures, codecs, hashes, binary range limits, compression, ZIP, and generic sequential callbacks/function values.
- `runtime/library_test.go`: malformed strict encodings/numbers, signed 64-bit binary boundaries, surrogate/duplicate-key JSON validation, PBKDF2 vector, AEAD tampering, Ed25519, compression trailing bytes/bombs, ZIP/TAR paths/limits, exclusive filesystem writes, symlink-safe removal, HTTP duplicate headers/status/redirect/limits, and TCP half-close/round-trip, empty/oversized UDP datagrams, socket close/cancellation, and Network close interrupting active HTTP requests.
- `tests/e2e/testdata/projects/library/main.ms`: native CLI acquisition/use of FileSystem, Entropy, WallClock/Timestamp and System roots, including exclusive creation and removal.
- `compiler/library_test.go`: every registered function is importable, and opaque BigInt/Regex/Timestamp constructors are rejected.
- Existing host, service, compiler/cache and e2e tests remain required. The runtime embeds all new implementation sources for standalone builds and content pinning; test sources are excluded from the runtime bundle.

Run `go test ./...`, `go test -race ./runtime ./checker ./compiler ./tooling`, and `go vet ./...` with Go 1.25 or newer. Native platform limitations are documented per package rather than inferred from a familiar module name. Written future requirements are not counted as passed tests.

Networking checks additionally cover scoped host/CIDR policy (including raw-IP bypass rejection), custom DNS records, listener reuse after timeout, Unix half-close, cancellation during acquisition, pooled cookies/redirects, HTTP/2, custom trust/hostname validation, mutual TLS, duplex streamed upload/response, decompressed WebSocket bounds and shutdown joining hijacked sessions. `tests/e2e/testdata/projects/networking/main.ms` exercises HTTP streaming and WebSocket echo through the compiler and an offline native build.
