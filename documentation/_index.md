+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Agents write it and people understand it. A small typed language with failure, mutation and copies marked in the source, compiler feedback an agent can act on, code maps for review, and fast native builds."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"check"} -->
```manuscript {filename="server.ms"}
import open from "@std/os/fs.ms"
import serve from "@std/net/net.ms"
import HttpExchange, headers from "@std/net/http.ms"

fn notes(var exchange: HttpExchange) Unit!:
    var chunks = try (try open("notes.txt", "r", 0)).reader()
    try exchange.send_headers(200, headers())
    for chunk in chunks.wait():
        try exchange.write_bytes(try chunk)
    return ok(unit)

fn run() Unit!:
    let server = try serve(":8080", notes)
    return server.wait()

export fn main() Int:
    return if run().is_ok(): 0 else: 1
```
{{< /docs-home >}}
