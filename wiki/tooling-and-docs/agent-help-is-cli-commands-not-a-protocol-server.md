[Wiki](../index.md) › [Tooling and docs](index.md)

# Agent help is CLI commands, not a protocol server

Decision: the user evaluated an MCP server (PR #528), judged the CLI the better surface for coding agents, and had it removed. Agents with a shell already get compact output from `check`, `lint`, `fmt`, and `test`; the gaps became `ms search_symbol` and `ms guide`. Navigation is by name, not `file:line:col`, because agents track names better than positions; `ms search_symbol` wraps workspace symbols, definition and references, and the next language-server feature to expose is a checked rename.

Apply when: adding agent-facing commands, changing search ranking, or touching the cheat sheet or standard-library index.

Verified: supplemental standard-library matches must share the CLI's result budget with project matches. Reserving a minimum of two library results made `--limit 1` return two matches and a full ten-project-result list grow to twelve. The [CLI limit regression](../../crates/ms-cli/tests/search_symbol.rs) checks library-only and project-filled lists, text output, and the cap at ten.

Evidence: [search](../../crates/ms-tooling/src/guide/search.rs), [workspace queries](../../crates/ms-lsp/src/workspace.rs), [project search regressions](../../crates/ms-lsp/tests/search_symbol.rs), [guide](../../crates/ms-tooling/data/cheatsheet.md), [search_symbol CLI tests](../../crates/ms-cli/tests/search_symbol.rs), [agent commands](../../documentation/developer-tooling/implementation.md#commands-for-agents).
Verify: `cargo nextest run -p ms-lsp -p ms-tooling -p ms-cli`; search tests pin typo, synonym, partial, and dedup behavior; compare release timings and output for project, standard-library and no-match queries in a large source tree. The cheat sheet's program must check and stay short.
