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

A command is a typed value `Command[T]`: `T` is the options struct its handler receives. Flags and positionals are declared once; a `build` function maps the parsed `Matches` to `T`. Commands are ordinary values, so they compose: a function can return a command, flag groups are reusable lists, and `Command[A]` and `Command[B]` nest under one parent through type erasure (`node()`).

```manuscript
type ServeOptions:
    port: Int
    mode: String
    root: String
    verbose: Bool

def serve_command() -> Command[ServeOptions]:
    return Command(
        name: "serve",
        about: "Run the server",
        flags: common_flags() + [Flag.int("port", short: "p", default: 8080), Flag.choice("mode", ["dev", "prod"], default: "dev")],
        args: [Arg.required("root")],
        build: lambda m: ok(ServeOptions(port: m.int("port"), mode: m.string("mode"), root: m.arg("root"), verbose: m.bool("verbose"))),
        run: lambda o: serve(o)
    )

def main() -> Unit:
    let app = Command.group("tool", about: "Manage projects", flags: [Flag.bool("verbose", short: "v", persistent: true)], children: [serve_command().node(), remote_command()])
    exit(app.execute(arguments()))
```

Composition rules:

- `Command[T].node() -> Node` erases `T` by capturing `build` and `run` in a closure (verified: `ms check` accepts generic types holding `Callable` fields and a method returning a closure over them).
- `Command.group(...)` has children and no `run`; leaves have `build` + `run`. Any command, group or leaf, can be a child of another, to any depth, and the same `Node` can be mounted under several parents.
- `common_flags()`-style functions return `List[Flag]`; persistent flags on a parent are visible to every descendant's `build` through `Matches`.
- Because handlers take `T`, they are plain functions testable without parsing: `serve(ServeOptions(...))`.
- Optional `Command.parse(argv)` on a leaf returns `Result[T, CliError]` for unit tests.

Semantics, one rule each:

- **Tree**: `Command.command(child)` nests without depth limit. Resolution takes the longest chain of leading non-flag words that name subcommands; the rest are that command's positionals. A command with children and no `run` prints its help.
- **Flags**: `--name value`, `--name=value`, `-p value`, `-p=value`, `-pvalue`, clustered shorts `-abc` for bools, `--no-name` for bools, `--` ends flags. Kinds: `Flag.bool`, `string`, `int`, `float`, `choice`, and `list` (repeatable). Each takes `short:`, `default:`, `help:`, `required:`, `persistent:`.
- **Persistent flags** (cobra): declared on a parent, valid on every descendant, may appear before or after the subcommand word.
- **Positionals**: `Arg.required`, `Arg.optional`, and `Arg.rest` (variadic, last only). Count and order are validated.
- **Matches** (used inside `build`): `string(name)`, `int`, `bool`, `float`, `list`, `arg(name)`, `rest()`, `path()`. Unknown names fault, since the schema is the caller's own code. `build` may return `CliError` for cross-field validation.
- **Help**: `-h` and `--help` are built in and generate `Usage:`, description, `Commands:`, `Arguments:`, `Flags:` (with defaults and choices), and inherited persistent flags. `help` as a subcommand word (`tool help remote add`) works too. Output is deterministic text (golden-testable).
- **Errors**: `CliError` is a `type` implementing `Error`: `UnknownFlag`, `UnknownCommand` (with nearest-name suggestion), `MissingValue`, `InvalidValue`, `MissingRequired`, `TooManyArguments`. `execute` prints the message plus a usage hint to stderr and returns exit code 2; `--help` returns 0.
- **API layers**: `Node.dispatch(argv) -> Result[Int, CliError]`, `Node.execute(argv) -> Int` (resolve, build `T`, handle help and errors, run), `Node.render_help(path) -> String`.
- **Handlers**: `Callable[[T], Result[Int, CliError]]` (`ms check` rejects `String` as the error type; it must implement `Error`). `Ok(code)` is the exit code; `Err` prints and exits 1.

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

- Handler error type: `CliError` only, or any `Error` via a wrapper variant (recommend the wrapper).
