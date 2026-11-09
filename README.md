# Manuscript

**The language for the agentic era.**

<p align="center">
  <img src="website/static/images/screencast.gif" width="720" alt="A screencast of Manuscript: failure as values, ownership errors, promises, ms verify, the call graph and a native build, each with a short caption.">
</p>

Manuscript makes it practical to trust agent generated code: its syntax is simple enough to read at a glance, and built-in diagramming tools with an interactive code map let you explore what the agent built without reading it line by line. Under the hood, the compiler enforces one owner per value with no GC, so programs run close to C speed and scale to all cores, and a simple effects system tracks what your code is allowed to do. The toolchain comes with everything agentic coding needs: errors that name their fix, and one command each to verify, test, fuzz, benchmark and profile.

Builds are fast. A generated 122,000-line project builds in debug in 5.4 s against 9.0 s for `go build` ([results](bench/perf/results-2026-11-05.md)).

```manuscript
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

type Config:
    port: Int?

fn port_from(text: String) Int!:
    let config = try parse[Config](text)
    return ok(config.port.get(8080))

test "an unset port uses the default":
    let port = try port_from("\{\"port\":null\}")
    try expect_equal(port, 8080)
```

Save it as `config.ms` and run `ms test config.ms`.

## Where to go next

- [Install and run a first program](documentation/learn/getting-started.md)
- [Why Manuscript](documentation/learn/why-manuscript.md): an agent builds a program, from first mistake to shipped executable
- [Guide](documentation/guide/_index.md): one small program, chapter by chapter
- [Performance](bench/perf/README.md) and [agent benchmark](bench/agent/README.md): methods, revisions and reproduction commands
- [Vision](VISION.md)

The language, toolchain and standard library work today and are hardened with each release; syntax and APIs still evolve.
