# Manuscript

**AI writes more code. You still have to understand it.**

A native programming language built for agents to write and humans to understand.

Get readable source, compiler feedback your agent can act on, and checked facts to help you review the next change.

[Try Manuscript](documentation/learn/getting-started.md) · [Rust performance](#native-speed-measured-against-rust) · [How we're building it](#built-with-agents-improved-through-evidence)

*Alpha: syntax and APIs can change. The first native build downloads pinned tools; see the setup guide for platform requirements.*

## Why the language matters

The language determines what an agent must express, what the compiler can reject and what a reviewer can see. Manuscript brings familiar syntax, explicit ownership, errors and scoped concurrency into one design, with the compiler's knowledge available through the same CLI.

## Give your agent a clearer target

An agent can look up actual project and library APIs with `ms search_symbol`, get diagnostics that name the cause and remedy, and apply available mechanical repairs with `ms check --fix`. A small, regular language and source-backed tools give it concrete rules to work with.

## Native speed, measured against Rust

**As fast as Rust on the measured tree and map-counting workloads.** The published run also shows where Rust is ahead:

| Workload | Manuscript | Rust |
| --- | ---: | ---: |
| Binary trees | 26.1 ms | 30.0 ms |
| Map counting | 14.4 ms | 23.8 ms |
| Collatz | 242.7 ms | 178.6 ms |

Recorded on four-core Linux at `c1b81215` (October 25): LLVM Release versus Rust at `opt-level=3`. The harness requires matching checksums across versions. The full seven-kernel results include both default and overflow-checked Rust, with source and reproduction commands. [See the measurements](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25).

## Understand what it built

This small CLI lists failed jobs from a JSON report. You can follow the input shape, filtering and error path in one file. Save it as `jobs.ms`:

```manuscript
from "@std/io.ms" import stdout
from "@std/json.ms" import parse
from "@std/process.ms" import arguments
from "@std/testing.ms" import expect_equal

type Job:
    name: String
    status: String

export def failed_jobs(text: String) -> Result[String, Error]:
    let jobs = try parse[List[Job]](text)
    let failed = jobs.filter(lambda job: job.status == "failed")
    return ok(failed.map(lambda job: job.name.clone()).join(", "))

def run() -> Result[Unit, Error]:
    let text = arguments().get(0, default: "[]")
    let names = try failed_jobs(text)
    try stdout().write(f"{names}\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error(): return 1
    return 0

test "malformed reports fail":
    try expect_equal(failed_jobs("not JSON").is_error(), True)
```

```sh
ms run jobs.ms -- '[
  {"name":"build","status":"failed"},
  {"name":"test","status":"passed"}
]'
```

```text
build
```

`try` propagates a malformed report as an error; `.clone()` makes the copied name explicit. Run the inline test with `ms test jobs.ms`, then build the executable with `ms build jobs.ms -o jobs`.

## Change it with compiler-backed evidence

Suppose an agent changes this program to return an error instead of silently treating malformed JSON as an empty report. `ms review` compares the checked before and after versions, identifying changes to contracts, effects, error flow and resource scopes:

```sh
git diff --no-renames | ms review jobs.ms --diff -
```

Captured from that change, an excerpt of the report:

```text
5. ERROR FLOW
   failed_jobs error type: none -> Error
   failed_jobs try sites: 0 -> 1
   run try sites: 1 -> 2
```

These are facts derived from checked source. The report tracks static properties; tests and human review still decide whether the change is right. [Review workflow and limits](documentation/developer-tooling/implementation.md#review-report).

## Built with agents. Improved through evidence.

We use coding agents to build Manuscript itself, guided by shared [repository skills](skills/README.md) and [recorded lessons](.experts/README.md). Real tasks expose friction in the language, APIs and diagnostics; those observations feed the next design change.

The separate [agent benchmark](bench/agent/README.md) starts fresh workspaces, runs programs against hidden tests, and records pass rates, first-build success, tokens, turns and cost. Its [dated results](bench/agent/results/summary-2026-10-22.md) include failed attempts and source-size costs. This measures how agents write programs; the native benchmarks above measure how fast those programs run.

The compiler is written in Rust; standard-library declarations and many implementations are written in Manuscript. Changes are checked with unit tests, source-conformance fixtures and native examples, while performance work gets reproducible measurements. [Architecture](documentation/contributing/architecture.md) · [Development checks](documentation/contributing/development.md).

## Try it on one real task

Ask your agent to build a small CLI you would actually use. Read the source, run its checks, and inspect the next change.

[Get the compiler](documentation/learn/getting-started.md), then start a project:

```sh
ms init my-app
cd my-app
ms verify ms.toml
ms build ms.toml -o my-app
```

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) · [Project vision](VISION.md)
