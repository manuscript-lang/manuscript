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
import buffered, text, HttpRequest, HttpResponse from "@std/net/http.ms"

fn hello(request: HttpRequest) HttpResponse:
    return text(200, "Hello from {request.path}")

export fn main() Int:
    serve(":8080", buffered(hello)).get().wait().get()
    return 0
```
{{< /docs-home >}}
