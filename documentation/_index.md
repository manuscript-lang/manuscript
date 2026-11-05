+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Agents write it and people understand it. A small typed language with failure, mutation and copies marked in the source, compiler feedback an agent can act on, code maps for review, and fast native builds."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"check"} -->
```manuscript {filename="server.ms"}
import serve from "@std/net/net.ms"
import buffered, text from "@std/net/http.ms"

export fn main() Int:
    let server = serve(":8080", buffered(fn request: text(200, "Hello from {request.path}\n"))).get()
    return if server.wait().is_ok(): 0 else: 1
```
{{< /docs-home >}}
