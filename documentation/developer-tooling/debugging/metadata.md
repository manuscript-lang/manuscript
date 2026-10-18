+++
title = "Build, source, and task metadata"
weight = 118
+++

# Build, source, and task metadata

- `ms inspect <module-or-project>` emits format-1 JSON: build identity, source hashes, deterministic entity IDs, generated declaration and local names, types, call sites including implicit cleanup, conservative transitive effects, and statement header spans (half-open original-byte ranges excluding line terminators).
- `ms diagram` emits the static call graph as ascii (default) or Mermaid (`--format mermaid`).
- Native checked builds emit a separate executable and toolchain manifest.

- Generated Go uses line directives, so Delve maps native lines to `.ms` statements. Locals keep source names.
- `--debug` keeps native symbols, disables optimization and inlining, and uses absolute source paths.
- Only the VS Code adapter (`extensions/vscode/debug-adapter.js`) shows records, collections, and variants as Manuscript values; interactive `ms debug` and `ms dap` clients see Delve's Go values.
- Scripted `ms debug` (`--break`, `--script`) reports source function names, local names and types, and only Manuscript frames; scalars render directly, others use Delve's one-line form.
