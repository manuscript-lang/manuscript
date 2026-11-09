# Manuscript

**The language for the agentic era.**

Manuscript makes it practical to trust agent generated code: its syntax is simple enough to read at a glance, and built-in diagramming tools with an interactive code map let you explore what the agent built without reading it line by line. Under the hood, the compiler enforces one owner per value with no GC, so programs run close to C speed and scale to all cores, and a simple effects system tracks what your code is allowed to do. The toolchain comes with everything agentic coding needs: errors that name their fix, and one command each to verify, test, fuzz, benchmark and profile.


<p align="center">
  <img src="website/static/images/screencast.gif" width="720" alt="A screencast of Manuscript: failure as values, ownership errors, promises, ms verify, the call graph and a native build, each with a short caption.">
</p>


```manuscript
fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), "hello {request.path}".to_bytes())

fn listen() Unit!:
    let server = try serve("127.0.0.1:0", buffered(handle))
    print("{server.address()}")
    try server.wait()
    return ok(unit)

export fn main() Int:
    if listen().is_ok(): return 0
    return 1
```

## Where to go next

- [Install and run a first program](documentation/learn/getting-started.md)
- [Why Manuscript](documentation/learn/why-manuscript.md): an agent builds a program, from first mistake to shipped executable
- [Guide](documentation/guide/_index.md): one small program, chapter by chapter
- [Performance](bench/perf/README.md) and [agent benchmark](bench/agent/README.md): methods, revisions and reproduction commands
- [Vision](VISION.md)

The language, toolchain and standard library work today and are hardened with each release; syntax and APIs still evolve.
