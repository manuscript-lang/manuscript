+++
title = "General-purpose packages"
weight = 47
+++

# General-purpose packages

[Standard library guide](../_index.md) · [Package coverage](coverage.md)

Find a package by the task you want to perform. Read [common contracts](contracts.md) for shared error and limit rules, and [coverage](coverage.md) to compare available functionality with Node.js or Go. The signature blocks are reference declarations, not complete programs.

- [Text, bytes, and collections](data.md) — Work with text, bytes, encodings, collections, and regular expressions.
- [Numbers and mathematics](math.md) — Use floating-point functions and arbitrary-precision integers.
- [Serialization and formats](formats.md) — Parse and write JSON, CSV, and URLs; parse HTML trees and escape text.
- [Paths and filesystem](filesystem.md) — Manipulate paths and use an explicit filesystem service.
- [Time and system information](system.md) — Work with timestamps and query supplied clock or system services.
- [Cryptography and randomness](crypto.md) — Hash, authenticate, encrypt, sign, and request random bytes.
- [Networking and TLS](network.md) — Use destination policies, DNS, sockets, and verified TLS.
- [HTTP](http.md) — Send requests and serve buffered or streaming responses.
- [WebSocket sessions](websocket.md) — Send and receive messages within a WebSocket session lifetime.
- [Command-line programs](cli.md) — Define main, import services, and handle exit and shutdown.
- [Subprocesses and terminal I/O](process.md) — Read terminal streams and run commands through explicit authority.
- [Compression and archives](archive.md) — Compress data and handle archive entries with explicit limits.
- [Logging, testing, and diagnostics](tooling.md)

## Read a signature

For example, `fn parse(text: String, limits: Optional[JsonLimits]) -> Result[JsonValue, JsonError]` means:

- Call the function with named `text` and `limits` arguments.
- Success returns a `JsonValue`; an expected failure returns a `JsonError`.
- Import the function from the module listed above its signature. Import type names separately if your own annotations use them.

A heading such as “FileSystem operations” lists methods on a supplied service. Importing its interface gives you the type; obtain the service value from the host or a function parameter. Read the behavior sections for limits, cleanup, and partial effects.

- [Filesystem, OS, process, paths, and timers](node-host.md) — Node.js 24 API mapping, bounded handles, explicit process authority, timer lifetimes, and platform limits.
