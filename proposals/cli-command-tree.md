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

A command is a typed record `Command[T]`: `T` is the options struct its handler receives; `build` maps parsed `Matches` to `T`. Flags and arguments are plain records, not constructors, because Manuscript has no static methods (`Flag.choice(...)` does not exist). Examples below were checked with `ms check` against stub declarations of exactly these types (every line is accepted; bodies of `execute`/parsing are the stubbed part).

```manuscript
type ServeOptions:
    port: Int
    mode: String
    root: String
    verbose: Bool

def common_flags() -> List[Flag]:
    return [Flag(name: "verbose", kind: FlagKind.Bool, short: "v", persistent: True)]

def serve_command() -> Command[ServeOptions]:
    return Command(
        name: "serve",
        about: "Run the server",
        flags: [
            Flag(name: "port", kind: FlagKind.Number, short: "p", default: "8080"),
            Flag(name: "mode", kind: FlagKind.Choice(["dev", "prod"]), default: "dev")
        ],
        args: [Arg(name: "root")],
        build: lambda m: ok(ServeOptions(port: m.int("port"), mode: m.string("mode"), root: m.string("root"), verbose: m.bool("verbose"))),
        run: lambda o: serve(o)
    )

def main() -> Int:
    let app = Node(name: "tool", about: "Manage projects", flags: common_flags(), children: [serve_command().node()])
    return app.execute(arguments())
```

Types (all in `stdlib/cli.ms`, source-only):

- `Flag(name, kind, short = "", default = "", help = "", required = False, persistent = False)`; `FlagKind` is `Bool | Text | Number | Choice(options) | Many` (`Many` repeats).
- `Arg(name, help = "", required = True, rest = False)`; only the last arg may be `rest`.
- `Matches` reads parsed values inside `build`: `string`, `int`, `float`, `bool`, `list`, `rest`, and `path()` (resolved subcommand chain). An unknown name faults, since the schema is the caller's own code.
- `Node(name, about, flags, args, children, exec)` is the untyped, composable unit. A group is a `Node` with `children` and no `exec`.
- `Command[T].node() -> Node` erases `T` by closing over `build` and `run` (verified to check, including the recursive `children: List[Node]`).
- `Node.execute(argv) -> Int` resolves, parses, builds `T`, runs, and returns the exit status, so `main() -> Int` returns it directly (the guide's contract; no `exit` call).
- `Node.dispatch(argv) -> Result[Int, CliError]` is the same without printing, and `Node.help(path) -> String` renders help, for tests.

Composition: commands and groups are values, so functions return them, flag lists concatenate (`common_flags() + [...]`), and one `Node` can be mounted under several parents. Handlers take `T`, so `serve(ServeOptions(...))` is testable without parsing.

Rules:

- **Resolution**: leading words that name children descend the tree; remaining words are positionals of the reached node. A group with no `exec` prints its help. Depth is unlimited.
- **Flags**: `--name value`, `--name=value`, `-p value`, `-p=value`, `-pvalue`, clustered short bools `-abc`, `--no-name` for bools, `--` ends flags. Persistent flags declared on a node are accepted at that node and every descendant, before or after the subcommand word.
- **Help**: `-h` and `--help` are built in and render Usage, description, Commands, Arguments, and Flags with defaults and choices; `tool help remote add` also works. Output is deterministic (golden-testable). Exit 0.
- **Errors**: `CliError` implements `Error` with `UnknownFlag`, `UnknownCommand` (nearest-name suggestion), `MissingValue`, `InvalidValue`, `MissingRequired`, `TooManyArguments`, and `Failed(cause)`. `execute` writes the message and a usage hint to stderr and returns 2. `run` returns `Result[Int, CliError]`: `ok(code)` is the status; `error(e)` prints and returns 1. A handler's own `Error` is wrapped with `Failed(...)`.
- **Ownership**: values are owned `String`/`List`; `node()` clones what it keeps. No natives, so Linux, macOS, and Windows are identical; `/flag` Windows forms are not supported.

Naming follows the stdlib: plain options-record construction with defaults (as `FetchOptions`), one spelling (`process.arguments()` stays the only argv source), `Result[_, E: Error]` with a domain error type.

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

- **Builder methods on `Command`** (`cmd.int_flag(...)`): needs one method per kind on both `Command` and `Node`; records plus a flag list compose by concatenation instead. Revisit if verbose.
- **Do nothing**: every program re-implements parsing; agents produce inconsistent, error-prone CLIs. Rejected.
- **Struct-derived parsing**: needs reflection or macros Manuscript lacks; `build` is the explicit form. Rejected.
- **Flags only (Go `flag`)**: no subcommands or help hierarchy, the stated requirement. Rejected.
- **Native Rust parser**: contradicts Manuscript-first; no primitive is missing. Rejected.

## Staging and verification

1. Types, `Matches`, `CliError`, `dispatch`; fixture tests. Gate: tests green on all platforms.
2. Help generation, `help` word, suggestions, `execute`; golden tests.
3. Docs page and example app; `make verify`.

## Open questions

- None for the owner: no language or runtime behavior changes.
