# `@std/cli.ms`: command trees, flags, positionals, generated help

## Summary

- Today a program gets `process.arguments() -> List[String]` and nothing else; every CLI hand-rolls parsing, usage text, and subcommand dispatch (for example `tests/conformance/fixtures/repo/scripts-conformance.ms`).
- Add `@std/cli.ms`, written entirely in Manuscript (no new Rust, no syntax change): a declarative `Command` tree with nested subcommands, typed flags, positional arguments, and generated help and usage.
- Modeled on Go's cobra (command tree, persistent flags, per-command handler) and JS yargs (typed options, defaults, choices, required, generated help).
- Cost: one stdlib module plus docs and tests. Decision requested: approve the API shape below before implementation.

## Status

Implemented in the first PR (parse, help, `execute`), 2026-10-26, checked against `main` (no `@std/cli.ms`; `grep -n args stdlib/process.ms` shows only `arguments()`). Direction: "do we a good cli arg parsing api? we should make it easy to build applications that have deep arg hierarchies and structures, cobra from go or yargs in js seems like a good reference".

## Problem

- No flag, subcommand, positional, or help support exists in `stdlib/`. Users must write string matching by hand.
- Non-goals: shell completion scripts, config-file and environment merging, interactive prompts, man pages, parsing into user structs by reflection.

## Design

One record, `Command`, is both a leaf and a group. A leaf sets a typed handler with the generic method `handle[T]`; `build` maps parsed `Matches` to your own options record `T`, and `run` receives it. `T` exists only inside that call, so commands with different option records mount under one parent with no second type or erasure step. Flags and arguments are plain records because Manuscript has no static methods.

```manuscript
type ServeOptions:
    port: Int
    mode: String
    root: String

def serve_command() -> Command:
    var command = Command(
        name: "serve",
        about: "Run the server",
        flags: [
            Flag(name: "port", kind: FlagKind.Int, short: "p", default: "8080"),
            Flag(name: "mode", kind: FlagKind.Choice(["dev", "prod"]), default: "dev")
        ],
        args: [Arg(name: "root")]
    )
    command.handle(
        build: lambda m: ok(ServeOptions(port: m.int("port"), mode: m.string("mode"), root: m.string("root"))),
        run: lambda options: serve(options)
    )
    return command

def main() -> Int:
    let flags = [Flag(name: "verbose", kind: FlagKind.Bool, short: "v", persistent: True)]
    return Command(name: "tool", flags: flags, children: [serve_command()]).execute(arguments())
```

The module is implemented in `stdlib/cli.ms` with a fixture, `tests/e2e/testdata/stdlib/cli.ms`, and a runnable recipe in `documentation/learn/common-tasks.md`.

Surface:

- `Flag(name, kind, short = "", default = none, help = "", required = False, persistent = False)`; `FlagKind` is `Bool | Text | Int | Float | Choice(options) | Many`. Values are validated against the kind at parse time.
- `Arg(name, help = "", required = True, rest = False)`.
- `Command(name, about, flags, args, children, exec)`; `handle(build:, run:)` sets `exec`. A command with `children` and no extra words prints help.
- `Matches`: `string`, `int`, `float`, `bool`, `list`, `string_or_none`, `int_or_none`, `float_or_none`, `path`. A name outside the schema or the wrong kind faults (programmer error). Typed `Flag[T]` handles are the deferred alternative.
- `Command.parse(argv) -> Result[Parsed, CliError]` (pure; `Parsed` is `Help(text)` or `Run(node, matches)`), `Command.execute(argv) -> Int`, `Command.help(path) -> Optional[String]`.
- `execute` writes help to stdout (status 0), usage errors plus a hint to stderr (2), and a handler `Error` message to stderr (1). `main() -> Int` returns it.
- Flags: `--name value`, `--name=value`, `-p value`, `--no-name`, `--`. Persistent flags apply to descendants before or after the subcommand word. Clustered shorts and suggestions are deferred.
- `parse` first validates the schema (`CliError.InvalidSchema`): duplicate names or shorts, reserved `help`/`-h`, misplaced `rest` or required args, defaults that do not fit their kind.
- `.experts/stdlib-design.md` records that an old `cli` module was merged into `process` (#659). That module only returned argv, which stays `process.arguments()`; `@std/cli.ms` parses a list it is given.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/cli.ms` | new source-only module with guide comment and per-member doc examples | `tests/e2e/testdata/stdlib/cli.ms` fixture: parsing, errors, help goldens |
| `stdlib/bindings.json`, `ms-rt` | unchanged (no natives) | n/a |
| `crates/ms-check` build embed | picks up new `.ms` automatically | stdlib check in `make verify` |
| `documentation/` | tutorial page; reference generated from `stdlib/cli.ms` comments | `make docs-check` |
| `examples/` | one multi-level example app | e2e run |
| Parser, checker, lowering, runtime, formatter, LSP | unchanged | n/a |

## Alternatives

- **Handler takes `Matches` directly**: no `build`, but handlers read strings by name; the stated requirement is a structured value. `handle[T]` keeps one `Command` type and adds the record.
- **`Command[T]` plus type-erased `Node`**: first draft; two types for what `handle[T]` does in one.

- **Builder methods per flag kind** (`cmd.int_flag(...)`): one method per kind; records in a list compose by concatenation instead. Revisit if verbose.
- **Do nothing**: every program re-implements parsing; agents produce inconsistent, error-prone CLIs. Rejected.
- **Struct-derived parsing**: needs reflection or macros Manuscript lacks; `build` is the explicit form. Rejected.
- **Flags only (Go `flag`)**: no subcommands or help hierarchy, the stated requirement. Rejected.
- **Native Rust parser**: contradicts Manuscript-first; no primitive is missing. Rejected.

## Staging and verification

One PR: module, fixture, recipe. Follow-ups on demand: clustered shorts, suggestions, typed `Flag[T]` handles.

Checks: `ms test tests/e2e/testdata/stdlib/cli.ms`, `make docs-check`, `make repo-check`, `cargo test --workspace` (runs the documentation example).

## Open questions

- None for the owner: no language or runtime behavior changes. Typed `Flag[T]` handles are the follow-up if string-keyed `Matches` proves error-prone.
