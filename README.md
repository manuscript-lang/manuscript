# Manuscript

**The language for the agentic era.**

A statically typed, natively compiled language designed for agents to write and humans to understand.

[Get started](documentation/learn/getting-started.md) · [Read the book](https://manuscript-lang.github.io/manuscript/) · [Releases](https://github.com/manuscript-lang/manuscript/releases)

*Manuscript is in alpha. Syntax and APIs can change; these docs follow `main`, and releases may lag behind.*

## Why Manuscript

### Familiar syntax. Native programs.

`def`, indentation and f-strings, with static types and native executables. [Take the tour](documentation/learn/tour.md).

### Feedback you can act on

Diagnostics name the cause and remedy. `ms check --fix` applies mechanical repairs; `ms search_symbol` finds project and standard-library APIs. [Tooling](documentation/developer-tooling/implementation.md#commands-for-agents).

### Ownership you can follow

`var` marks mutation, `.clone()` marks copies, and `with` scopes resources. Ordinary data needs no tracing garbage collector. [Ownership rules](documentation/core-language/types/references.md).

### Concurrency without `async`

Run tasks, worker threads or child processes in a `with` block. Communicate over typed channels. [Choose a boundary](documentation/core-language/concurrency/_index.md).

### Everyday tools included

The compiler, formatter, linter, test runner and growing standard library ship in one `ms` binary. Files, HTTP, JSON and command-line parsing are included.

## A small example

JSON decodes into a record; missing fields take their defaults. Save as `config.ms` and run `ms test config.ms`:

```manuscript
from "@std/json.ms" import parse
from "@std/test.ms" import expect_equal

type Config:
    host: String = "127.0.0.1"
    port: Int = 8080

test "read configuration with defaults":
    let config = try parse[Config]("{\"port\":9000}")
    try expect_equal(config.host, "127.0.0.1")
    try expect_equal(config.port, 9000)
    try expect_equal(parse[Config]("{\"port\":true}").is_error(), True)
```

## Try it

[Install `ms` and add it to your PATH](documentation/learn/getting-started.md), then:

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
ms test ms.toml
ms build ms.toml -o hello
```

The run prints `Arguments: 2`. The first native build downloads pinned tools into a cache. See the setup guide for platform requirements, including Windows, or [build from source](documentation/contributing/rust-toolchain.md#build-and-run).

## See the measurements

Results vary by workload and machine. The benchmarks include revisions, reproduction commands and the cases that still need work:

- [Native performance](bench/perf/README.md): kernels, JSON, HTTP, memory and worker scaling.
- [Agents writing code](bench/agent/README.md): hidden-test results, first-build success and source size.

## Go deeper

[Task recipes](documentation/learn/common-tasks.md) · [Language reference](documentation/core-language/_index.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)

[Project vision](VISION.md) · [Contributing](AGENTS.md) · [Development checks](documentation/contributing/development.md)
