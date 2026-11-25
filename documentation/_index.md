+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "A statically typed, natively compiled language with single ownership: no garbage collector and no lifetime annotations. Diagnostics name the cause and the fix."
+++

{{< docs-home part="hero" >}}

## A taste

A web server in a dozen lines. Each connection runs as its own promise across all cores.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import (
    HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
    serve from "@std/net/net.ms",
)

fn handle(request HttpRequest) HttpResponse {
    return HttpResponse(200, f"hello {request.path}".to_bytes())
}

fn main() Void! {
    server := serve("127.0.0.1:0", buffered(handle))?
    print(f"{server.address()}")
    server.wait()?
}
```

## What the compiler catches

<div class="home-taste">

Using a value after it moved is a compile error:

<!-- manuscript-example: {"mode":"error","contains":"is moved here"} -->
```manuscript
fn main() Void {
    var names = List[String]()
    first := "ada"
    names.append(first)
    print(first)
    // type: `first` is moved here but used again at 5:11
}
```

An effect must be allowed by every caller that reaches it:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import write_file from "@std/os/fs.ms"

// ms: effect db.write
// ms: allow_effect std.fs.write
fn save(order String) Void! {
    return write_file("orders.log", order).wait()
}

fn audit(total Int) Void! {
    return save(f"audit {total}")
    // ms lint: `audit` reaches db.write: audit -> save
}
```

</div>

Read on: [ownership and references](core-language/types/references.md), [errors as values](core-language/errors/_index.md), [effects](developer-tooling/source/effects.md), [diagnostics](developer-tooling/source/diagnostics.md) and [concurrency](core-language/concurrency/_index.md).

{{< docs-home part="proof" >}}

{{< docs-home part="paths" >}}

{{< docs-home part="status" >}}
