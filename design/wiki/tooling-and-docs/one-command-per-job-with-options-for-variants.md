[Wiki](../index.md) › [Tooling and docs](index.md)

# One command per job, with options for variants

Decision (2026-11-26, Chinmay): the `ms` CLI had 23 subcommands; it now has 15. A variant of one job is an option, not a command: `check` runs types, fmt and lint (`--only types|lint|fmt` picks one, `--test` adds the tests), `build --emit mir|ir` replaces `emit`, `run --profile` replaces `profile`, `map --view ...` replaces `diagram`, `review` and `inspect`, `help <code>` replaces `explain`, `search` replaces `search_symbol`, and `dev doc` holds the internal docgen input. The old names were removed with no aliases, as asked.

Verified: options that belong to one step (`--fix`, `--watch`, `--std`, `--with-text`, `--each`, `--syntax`, several inputs, and the `--json` schema of the type check) need `--only`; bare `ms check --json` is the multi-step document. Scripts that only want the type check must say `--only types`, or a formatting finding fails them.

Apply when: adding a command or flag, or writing a script, doc or test that runs `ms`. Prefer an option on the closest command; a new top-level command needs a job none of the 15 covers. Internal tools go under `ms dev`.
Evidence: `src/cli/command_routes.c`, `src/cli/help_text.c`, the fixtures under `tests/commands/`.
Verify: `ms --help` lists the 15 commands; `ms lint` is an unknown command.
