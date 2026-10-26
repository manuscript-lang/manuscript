# `@std/cli.ms`: command trees, flags, positionals, generated help

## Summary

- Today a program gets `process.arguments() -> List[String]` and nothing else; every CLI hand-rolls parsing, usage text, and subcommand dispatch (for example `tests/conformance/fixtures/repo/scripts-conformance.ms`).
- Add `@std/cli.ms`, written entirely in Manuscript (no new Rust, no syntax change): a declarative `Command` tree with nested subcommands, typed flags, positional arguments, and generated help and usage.
- Modeled on Go's cobra (command tree, persistent flags, per-command handler) and JS yargs (typed options, defaults, choices, required, generated help).
- Cost: one stdlib module plus docs and tests. Decision requested: approve the API shape below before implementation.

## Status

Proposal, 2026-10-26, checked against `main` (no `@std/cli.ms`; `grep -n args stdlib/process.ms` shows only `arguments()`). Direction: "do we a good cli arg parsing api? we should make it easy to build applications that have deep arg hierarchies and structures, cobra from go or yargs in js seems like a good reference".

## Problem

- No flag, subcommand, positional, or help support exists in `stdlib/`. Users must write string matching by hand.
- Non-goals: shell completion scripts, config-file and environment merging, interactive prompts, man pages, parsing into user structs by reflection.

## Design

A command is a value built by calling methods on a `var`. Parsing is a pure function of `argv`; running a handler is separate, so tests never touch the process.

```manuscript
from "@std/cli.ms" import Command, Flag, Arg, Matches
from "@std/process.ms" import arguments

def main() -> Unit:
    var app = Command("tool", about: "Manage projects")
    app.flag(Flag.bool("verbose", short: "v", help: "Print more", persistent: true))

    var serve = Command("serve", about: "Run the server")
    serve.flag(Flag.int("port", short: "p", default: 8080, help: "Listen port"))
    serve.flag(Flag.choice("mode", ["dev", "prod"], default: "dev"))
    serve.arg(Arg.required("root", help: "Directory to serve"))
    serve.run(lambda m: serve_cmd(m))

    var remote = Command("remote", about: "Manage remotes")
    var add = Command("add", about: "Add a remote")
    add.arg(Arg.required("name"))
    add.arg(Arg.required("url"))
    add.run(lambda m: add_cmd(m))
    remote.command(add)

    app.command(serve)
    app.command(remote)
    exit(app.execute(arguments()))
```

Semantics, one rule each:

- **Tree**: `Command.command(child)` nests without depth limit. Resolution takes the longest chain of leading non-flag words that name subcommands; the rest are that command's positionals. A command with children and no `run` prints its help.
- **Flags**: `--name value`, `--name=value`, `-p value`, `-p=value`, `-pvalue`, clustered shorts `-abc` for bools, `--no-name` for bools, `--` ends flags. Kinds: `Flag.bool`, `string`, `int`, `float`, `choice`, and `list` (repeatable). Each takes `short:`, `default:`, `help:`, `required:`, `persistent:`.
- **Persistent flags** (cobra): declared on a parent, valid on every descendant, may appear before or after the subcommand word.
- **Positionals**: `Arg.required`, `Arg.optional`, and `Arg.rest` (variadic, last only). Count and order are validated.
- **Matches**: `get_string(name)`, `get_int`, `get_bool`, `get_float`, `get_list`, `arg(name)`, `rest()`, and `path()` (the resolved subcommand chain). Unknown names fault, since the schema is the caller's own code.
- **Help**: `-h` and `--help` are built in and generate `Usage:`, description, `Commands:`, `Arguments:`, `Flags:` (with defaults and choices), and inherited persistent flags. `help` as a subcommand word (`tool help remote add`) works too. Output is deterministic text (golden-testable).
- **Errors**: `CliError` is a `type` implementing `Error`: `UnknownFlag`, `UnknownCommand` (with nearest-name suggestion), `MissingValue`, `InvalidValue`, `MissingRequired`, `TooManyArguments`. `execute` prints the message plus a usage hint to stderr and returns exit code 2; `--help` returns 0.
- **API layers**: `Command.parse(argv) -> Result[Matches, CliError]` (pure), `Command.execute(argv) -> Int` (parse, handle help and errors, run handler), `Command.render_help(path) -> String`.
- **Handlers**: `Callable[[Matches], Result[Int, Error]]`-style; exact return type fixed during Stage 1 to match how existing stdlib handlers report failure (see `router.ms`).

Ownership and platform: values are plain owned `String`/`List`; no native code, so Linux, macOS, and Windows behave identically. Windows `/flag` forms are not supported.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/cli.ms` | new module, all logic in Manuscript | `stdlib/test` unit tests: parsing, errors, help goldens |
| `stdlib/bindings.json` | unchanged (no natives) | n/a |
| `crates/ms-check` build embed | picks up new `.ms` automatically | stdlib check in `make verify` |
| `documentation/` | CLI guide page; API reference generated from comments | `make docs` |
| `examples/` | one multi-level example app | e2e run |
| Parser, checker, lowering, runtime, formatter, LSP | unchanged | n/a |

## Alternatives

- **Do nothing**: every program re-implements parsing; agents produce inconsistent, error-prone CLIs. Rejected.
- **Struct-derived parsing (clap derive)**: needs reflection or macros Manuscript lacks. Rejected.
- **Flags only (Go `flag`)**: no subcommands or help hierarchy, the stated requirement. Rejected.
- **Native Rust parser**: contradicts Manuscript-first; no primitive is missing. Rejected.

## Staging and verification

1. `Command`, `Flag`, `Arg`, `parse`, `Matches`, `CliError`; unit tests. Gate: tests green on all platforms.
2. Help generation, `help` word, suggestions, `execute`; golden tests.
3. Docs page and example app; `make verify`.

## Open questions

- Handler return type and exit-code convention (recommend `Result[Int, Error]`, `Err` prints and exits 1).
- Method-chaining builders are unavailable if methods return `Unit`; recommend `var` mutation as shown unless chaining already works (checked in Stage 1).
