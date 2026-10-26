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

One recursive record, `Command`, is both leaf and group. A leaf is built with the generic function `command[T](name:, run:, flags:, args:)`: `run` receives the options record `T`, and no conversion code is written. The parser stores every supplied flag and argument as a JSON literal under its name (dashes become underscores) and decodes `T` with `json.parse[T]`, the existing compiler-backed generic that builds records from text. A field with no matching value, or of the wrong type, fails the run with `CliError.InvalidSchema`; flags without a field (such as inherited persistent flags) are ignored. This is pure Manuscript: no Rust, no syntax change.

```manuscript
type ServeOptions:
    port: Int
    mode: String
    root: String
    verbose: Bool

def serve(options: ServeOptions) -> Result[Int, Error]:
    ...

def main() -> Int:
    let serve_command = command[ServeOptions](
        name: "serve",
        about: "Run the server",
        flags: [
            Flag("port", FlagKind.Int, "p", "8080", "Listen port"),
            Flag("mode", FlagKind.Choice(["dev", "prod"]), default: "dev")
        ],
        args: [Arg("root", "Directory to serve")],
        run: lambda options: serve(options)
    )
    let flags = [Flag("verbose", FlagKind.Bool, "v", persistent: True)]
    return Command(name: "tool", flags: flags, children: [serve_command]).execute(arguments())
```

Ceremony choices: `Flag` fields are positional-friendly (`name, kind = Text, short, default, help`); `Arg(name, help, required, rest)`; the tree is one expression; handlers are plain functions of `T`.

Surface (`stdlib/cli.ms`, fixture `tests/e2e/testdata/stdlib/cli.ms`, recipe in `documentation/learn/common-tasks.md`):

- `FlagKind`: `Bool | Text | Int | Float | Choice(options) | Many`; values are validated at parse time. Optional args and flags without a default map to `Optional[...]` fields; `Many` and rest args to `List[String]`.
- `Command(name, about, flags, args, children, exec)`; `exec` is the raw `Callable[[Matches], Result[Int, Error]]` for handlers that read `Matches` themselves.
- `Command.parse(argv) -> Result[Parsed, CliError]` (pure; `Parsed` is `Help(text)` or `Run(node, matches)`), `execute(argv) -> Int`, `help(path) -> Optional[String]`.
- `execute` writes help to stdout (0), usage errors plus a hint to stderr (2), and handler errors to stderr (1). `main() -> Int` returns it.
- Flags: `--name value`, `--name=value`, `-p value`, `--no-name`, `--`. Persistent flags apply to descendants. Clustered shorts and suggestions are deferred.
- `parse` validates the schema first (`CliError.InvalidSchema`): duplicates, reserved `help`/`-h`, misplaced `rest`/required args, defaults that do not fit their kind.
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

- **Handler takes `Matches` directly**: kept as the `exec` escape hatch; the stated requirement is a structured value.
- **Hand-written `build` lambda or `handle[T]` method**: earlier drafts; the user converted `Matches` to `T` by hand. JSON decoding removes it.
- **`Command[T]` plus type-erased `Node`**: first draft; `command[T]` returns an erased `Command` instead.

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
