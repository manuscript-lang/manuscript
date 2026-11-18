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
import buffered, headers, HttpRequest, HttpResponse from "@std/net/http.ms"
import serve from "@std/net/net.ms"

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, f"hello {request.path}".to_bytes())

fn main() Void!:
    server := serve("127.0.0.1:0", buffered(handle))?
    print(f"{server.address()}")
    server.wait()?
```

![A screencast of Manuscript: failure as values, ownership errors, promises, ms verify, the call graph and a native build, each with a short caption.](/images/screencast.gif "A short tour: errors, ownership, promises, ms verify, the call graph and a native build.")

## What the compiler catches

<div class="home-taste">

Using a value after it moved is a compile error:

<!-- manuscript-example: {"mode":"error","contains":"is moved here"} -->
```manuscript
fn main() Void:
    var names = List[String]()
    first := "ada"
    names.append(first)
    print(first)
    // type: `first` is moved here but used again at 5:11
```

An effect must be allowed by every caller that reaches it:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import write_file from "@std/os/fs.ms"

// ms: effect db.write
// ms: allow_effect std.fs.write
fn save(order: String) Void!:
    return write_file("orders.log", order).wait()

fn audit(total: Int) Void!:
    return save(f"audit {total}")
    // ms lint: `audit` reaches db.write: audit -> save
```

</div>

## See what the agent built

`ms diagram` writes one offline HTML file: your source beside checked types, calls and control flow, with a diff overlay that marks what changed. [Open the code map guide](developer-tooling/implementation.md#interactive-code-map).

```sh
ms diagram ms.toml --format html -o code-map.html
```

![The code map's Behavior view of a function: its branches, calls and exits beside its source, with the changed declarations listed on the left.](/images/code-map-behavior.png "The code map, Behavior view, with a diff overlay.")

{{< docs-home part="paths" >}}

{{< docs-home part="proof" >}}
