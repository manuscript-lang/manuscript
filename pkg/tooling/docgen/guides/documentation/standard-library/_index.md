+++
title = "Standard library"
weight = 3
+++

# Standard library

Find the APIs for what you want to build. For a complete first example,
start with the [task recipes](../learn/common-tasks.md); use these guides to
understand the behavior and tradeoffs behind each API.

## Choose a task

| You want to… | Start with |
| --- | --- |
| Write a command-line tool | [Command-line programs](cli.md), [files and paths](filesystem.md), and [byte streams](streams.md) |
| Transform data | [Text and collections](data.md), [building values](builders.md), and [numbers](math.md) |
| Read or write structured documents | [Data formats](formats.md): JSON, YAML, TOML, CSV, URLs, and HTML |
| Connect to a service | [HTTP](http.md), [WebSockets](websocket.md), or [sockets and TLS](network.md) |
| Run an external command | [Commands and processes](process.md) |
| Handle compressed files | [Compression and archives](archive.md) |
| Use clocks, system information, or random values | [Time and system information](system.md) and [cryptography](crypto.md) |
| Observe and test behavior | [Logging](logging.md) and [testing helpers](testing.md) |
| Run operations together | [Concurrent work](../concurrency/_index.md) |

## Read a guide, then look up a signature

Guides explain common use, errors, limits, and resource lifetimes. The
[API reference](reference/_index.md) gives exact declarations and member
documentation. From a terminal, use `ms search_symbol <name or words>` to
find an API, or `ms search_symbol json.parse` to read one declaration.

Standard [imports](imports.md) select the APIs in scope.
[External services](services.md) explains how to obtain filesystem, network,
and clock services. [Errors and limits](contracts.md) describes the contracts
shared across the library; [special call rules](call-rules.md) covers the few
APIs with additional compiler checks.
