# Import allow list

## Summary

- Problem: `opaque type` (#1920) makes a module the only way to build or read a value, but nothing stops agent code from importing the raw module the abstraction wraps. Chinmay, 2026-10-28: "this needs to be coupled with permission limitation wrt who can import what, otherwise it's not useful".
- Change: an `[imports]` table in `ms.toml` keyed by importer pattern, listing the module patterns each file may import. Checked once at import resolution for local, alias, and `@std` imports. No syntax change.
- Cost: array values in the manifest parser, one matcher module in `ms-driver`, one call in the loader.
- Decision requested: approve the table and the longest-literal-prefix rule.

## Status

- Implemented in this PR against main `f3e8d95e`. Design carried from `proposals/opaque-types.md` on PR #1853 (closed, superseded by #1920 for the keyword), including skeptic round 4's items: defined specificity, one shared check, module granularity stated.

## Problem

`types/disk.ms` wraps `@std/fs.ms` so every write is metered. Nothing today stops `src/leak.ms` from writing `import read_file from "@std/fs.ms"` and bypassing it; a review has to notice. The same holds for any layering rule (`src/api/**` must not import `src/db/**`).

Non-goals: redirecting imports (`@std/fs.ms` served as `types/disk.ms`), per-symbol lists, narrowing what an allowed module can do (`Network.restrict` does that at the value), and who may edit `ms.toml` (CODEOWNERS).

## Design

```toml
[imports]
"src/**"   = ["src/**", "types/**", "@std/collections.ms", "@std/string.ms", "@std/json.ms"]
"types/**" = ["@std/**", "types/**"]
"tests/**" = ["**"]
```

- Keys and values are project-relative path patterns with `/` separators; `*` matches within a segment, `**` any number of segments. Standard modules are matched by their `@std/name.ms` spelling (`crates/ms-driver/src/project/imports.rs`).
- The matching key with the longest literal prefix (text before the first `*`) decides; two matching keys with equal prefixes are an error at the import. A file matching no key, a project without the table, and a file without `ms.toml` are unrestricted.
- Relative imports and aliases are checked by resolved path (`load.rs` `import_module`, after `resolve_import`); `@std` imports are checked before the loader skips them. One predicate, `check_import`, serves both.
- Diagnostic at the import: "`src/leak.ms` may not import `@std/fs.ms`; ms.toml [imports] "src/**" allows only "src/**", "types/**", "@std/collections.ms", "@std/string.ms", "@std/json.ms", so import one of those or extend the list".
- The check runs wherever the manifest is read: `ms check ms.toml`, `build`, `test`, the language server (`ms-lsp` finds the manifest for every file). `ms check file.ms` reads no manifest today, so it applies neither aliases nor this list; unchanged here.
- Module granularity: allowing `@std/net.ms` allows any socket. The table limits what a file names; the owning module limits what it does.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/manifest.rs` | `[imports]` table, array values, pattern validation | `imports_table_parses_and_validates` (`tests/project_project.rs`) |
| `crates/ms-driver/src/project/imports.rs` (new) | glob matcher, rule selection, `check_import` | `glob_segments`, `most_specific_rule_decides`, `equal_prefixes_are_an_error` |
| `crates/ms-driver/src/load.rs` | check at both import sites | `import_allow_list_rejects_at_the_import_position` |
| `crates/ms-cli/tests/imports.rs`, `tests/imports/` | project fixture through `ms check` | both CLI tests |
| checker, lowering, runtime, formatter, LSP | unchanged (the loader feeds all of them) | existing |
| `documentation/developer-tooling/builds/project-configuration.md` | "Import allow list" section | `make docs` |

## Alternatives

- Do nothing: layering and raw-module bans stay prose.
- A lint rule with the same table: same work, but a lint is opt-in and runs after the check; the loader sees every import once.
- A deny list (`[stdlib] deny`, first draft): cannot express layering between project modules and grows with the stdlib. An allow list keyed by importer covers both.
- A redirecting import map: hides what code really calls; rejected by the owner.
- Drawback: a second config surface in `ms.toml`; an agent that may edit `ms.toml` is not restricted.

## Staging and verification

One PR. `cargo test -p ms-driver -p ms-cli`, `make verify`.
