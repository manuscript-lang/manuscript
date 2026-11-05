# Manuscript

**The language for the agentic era.**

Agents write it; people understand it. Manuscript is a small, statically typed language that compiles to native executables. Failure, mutation and copies are marked in the source, so a reader can see what a program does without reading every line. Diagnostics say what is wrong and how to fix it, and the toolchain gives an agent what it needs to work alone: `ms guide`, `ms search_symbol`, `ms check --fix` and `ms verify`. Interactive code maps and `ms review --diff` show a person what changed.

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
- [Coming from another language](documentation/coming-from/_index.md): TypeScript, Go and Python
- [Performance](bench/perf/README.md) and [agent benchmark](bench/agent/README.md): methods, revisions and reproduction commands
- [Vision](VISION.md)

The language, toolchain and standard library work today and are hardened with each release; syntax and APIs still evolve.
