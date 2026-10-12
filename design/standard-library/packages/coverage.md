+++
title = "Node.js and Go coverage"
weight = 60
+++

# Node.js and Go coverage

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

The implementation now offers broad equivalents for common Node.js/Go application work. It is not API compatibility or a claim that every Go package is present. This map distinguishes runnable functionality from remaining work.

| Node.js / Go capability | Manuscript option | Availability |
| --- | --- | --- |
| Buffer, bytes, encoding/hex/base64/binary | Immutable Bytes, strict UTF-8/hex/base64, binary Int/Float | Implemented |
| strings, Unicode scalar operations, regexp | Text functions and opaque RE2-style Regex | Implemented; normalization/graphemes/legacy encodings deferred |
| Array/Map/Set, slices/maps/sort | Immutable collections, sequential map/filter/fold/stable sort, builders | Implemented |
| Math, strconv, math/big | Float math, strict number conversion, BigInt, existing Decimal | Implemented; complex/advanced distributions deferred |
| JSON, encoding/json/csv, net/url, html | Exact-number JsonValue, bounded CSV, ordered query codecs, URL records, escaping | Implemented |
| path/filepath, fs/io/fs | Native pure paths, explicit read/write/copy/stat/list/create/remove/rename/links | Implemented; seek/watch/permissions APIs deferred |
| stream, io, bufio/readline | Existing ReadStream/WriteStream plus bounded copy/read_all/read_line | Implemented functional option; no Node stream events |
| time/timers/os/process info | Monotonic Clock/sleep, wall Timestamp, System snapshots/environment | Implemented; timezone/calendar/ticker APIs deferred |
| crypto/crypto/rand | Entropy, UUID, unbiased integers, SHA/HMAC/PBKDF2, AES-GCM, Ed25519 | Implemented; broader algorithms/key containers deferred |
| net/dgram/dns | TCP/Unix sockets, UDP, bounded DNS A/AAAA/CNAME/MX/NS/TXT/PTR/SRV, scoped resolver and destination policy | Implemented |
| tls/https | Verified TLS, custom trust/client certificates, mutual TLS listener, certificate parsing/verification and negotiated metadata | Implemented |
| http/net/http | Buffered and streaming HTTP/1.1/HTTP/2, pooled clients, cookies, redirects, WebSocket sessions | Implemented; HTTP/3 excluded by user request |
| child_process/os/exec | Existing Commands.run, bounded captured output, timeout, joined execution | Implemented functional option; interactive child handles deferred |
| zlib/compress, archive/tar/zip | Bounded gzip/zlib/deflate, ZIP/TAR immutable encode/decode | Implemented; extraction/Brotli/Zstd deferred |
| events/sync/channels/context/worker_threads | Queue, State, Pool/Lease, joined parallel and Background contexts | Implemented; no JS worker VM or detached tasks |
| console/log/assert/testing | Explicit streams/structured JSON log, equality/tolerance assertions, existing runner | Implemented; interactive terminal and advanced diagnostics deferred |
| XML/gob/ASN.1/MIME/image/database/sql | Application/adaptor implementations using Bytes/streams/capabilities | Deferred; not claimed as standard-package coverage |
| vm/v8/module/async_hooks/inspector/repl, Go reflect/unsafe/plugin/syscall | Ordinary suspending functions, checked source tooling, trusted host adapters | Runtime-specific APIs omitted; no sandbox VM equivalent claimed |

The canonical callable surface lives on the linked package pages. Existing host/service APIs retain their identities. Deferred entries stay explicit; future implementations should add declarations to the Manuscript standard library sources and matching native implementations, semantic/boundary tests, and source-level compiler conformance fixtures together. The distribution remains self-contained with pinned vendored Go dependencies; native builds need no downloads.
