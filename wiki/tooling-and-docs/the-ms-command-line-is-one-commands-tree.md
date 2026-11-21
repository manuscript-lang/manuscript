[Wiki](../index.md) › [Tooling and docs](index.md)

# The `ms` command line is one Commands tree

Decision (Chinmay, 2026-11-21): flags and arguments of `ms` are declared once, in the `Command` tree of `tools/ms/cli.ms` (`@std/cli/command.ms`), and read from `Matches`. No file under `tools/ms` hand-parses words; a missing feature goes into the Command module, not into the tool.

Apply when: adding a flag, an argument or a command, or writing a helper program under `tools/ms`.
Evidence: [the tree](../../tools/ms/cli.ms), [the check](../../tools/repo-check/checks_text.ms) (`raw_arguments` fails any other file that imports `arguments`), [golden output](../../tools/ms/cases.golden).
Verify: `ms run tools/ms-cli-check.ms` matches the Rust statuses; `make repo-check`.

- A target argument that defaults to `ms.toml` is `Arg(default: "ms.toml")`; there is no pre-parse rewriting of the command line. The Rust `ms` still receives `rust_arguments(root, matches)`, one canonical spelling (target first, `--name=value`, `--` last).
- A helper program declares or borrows a `Command` and calls `run_tool` or `run_program` from `cli.ms`; `tree_tool` reuses the `ms` flags of `diagram`, `review` and `search_symbol` with a leading input argument.
- Usage errors name the nearest command (`did you mean check?`) and point at the help of the deepest command the words select; that is `Command` behavior, not `main.ms`.
