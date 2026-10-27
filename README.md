# Manuscript

**The language for the agentic era.**

Manuscript is a native programming language designed to help agents write correct programs.

A small, regular language gives agents a clear target. The compiler rejects invalid code, actionable diagnostics guide the repair, and executable tests check the behavior. Readable source keeps you close to what they build.

[Try Manuscript](documentation/learn/getting-started.md) · [Rust performance](#native-speed-measured-against-rust) · [How we're building it](#built-with-agents-improved-through-evidence)

*Alpha: syntax and APIs can change. These examples follow current source; releases may lag. The first native build downloads pinned tools. [Setup and platform requirements](documentation/learn/getting-started.md).*

## Give agents a path to correct code

Manuscript moves correctness rules out of the prompt and into the language. A small, regular core makes types, errors and resource lifetimes explicit. The compiler catches concrete mistakes: incompatible values, missing `match` cases and discarded error results.

When something fails, the agent gets a cause and a suggested repair, with `--json` output for tools. `ms search_symbol` finds actual project and standard-library APIs; `ms check --fix` applies available mechanical fixes. The next attempt can start from evidence.

## Catch the mistake. Check the repair.

An agent writes a helper that saves a report and returns `"saved"`. But it forgets to handle a failed write. This function fragment is rejected:

```manuscript
def save_report(path: String, report: String) -> Result[String, Error]:
    filesystem().write_file(path, report)
    return ok("saved")
```

The diagnostic explains why and suggests a repair (excerpt):

> this statement discards `Result[Unit, FileSystemError]`, so a failure would be lost; write 'try ...' to propagate it, …

The repair is one word: `try` forwards the write error to the caller. Save this complete version as `report.ms`:

```manuscript
from "@std/fs.ms" import filesystem
from "@std/test.ms" import expect_true

def save_report(path: String, report: String) -> Result[String, Error]:
    try filesystem().write_file(path, report)
    return ok("saved")

test "a directory is not a report file":
    try expect_true(save_report(".", "report").is_error())
```

```sh
ms test report.ms
```

```text
RUN report.ms::a directory is not a report file
PASS report.ms::a directory is not a report file
1 tests, 0 failed
```

The compiler rejects the lost result; the test checks the repaired error path. For a whole project, `ms verify` combines checking, formatting, linting and executable tests. Compiling alone does not establish that a program does what you intended.

## Native speed, measured against Rust

**As fast as Rust on the measured tree and map-counting workloads.** The published run also shows where Rust is ahead:

| Workload | Manuscript | Rust |
| --- | ---: | ---: |
| Binary trees | 26.1 ms | 30.0 ms |
| Map counting | 14.4 ms | 23.8 ms |
| Collatz | 242.7 ms | 178.6 ms |

Recorded on four-core Linux at `c1b81215` (October 25): Manuscript LLVM Release versus Rust at `opt-level=3`. The harness requires matching checksums across implementations. The [full seven-kernel results](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25) include source, run commands and a separate overflow-checked Rust configuration.

## Built with agents. Improved through evidence.

We use coding agents to build Manuscript itself, with shared [repository skills](skills/README.md) and [recorded lessons](.experts/README.md). The compiler is written in Rust; standard-library declarations and many implementations are written in Manuscript.

Alongside native performance, we measure how agents write programs. The [agent benchmark](bench/agent/README.md) uses fresh workspaces and hidden tests, recording failures, build attempts, tokens and cost.

A passing solution and a clean first attempt are different outcomes. We publish [both, including failed attempts and reruns](bench/agent/results/summary-2026-10-22.md), and use the friction to improve the language, APIs, diagnostics and guidance. These coding evaluations are separate from execution-speed benchmarks.

Changes face [unit tests, source-conformance fixtures and native examples](documentation/contributing/development.md). [Explore the architecture](documentation/contributing/architecture.md).

## Try it on one real task

Give your agent a small CLI you actually need. Have it look up APIs, write tests and work through the compiler's feedback.

[Get the compiler](documentation/learn/getting-started.md), then start:

```sh
ms init my-app
cd my-app
ms verify ms.toml
ms build ms.toml -o my-app
```

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) · [Project vision](VISION.md)
