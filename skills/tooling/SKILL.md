---
name: tooling
description: Change Manuscript formatting, lint, inspection, LSP features, VS Code integration, CLI commands, or debugging against checked source.
---

# Tooling

Use for `pkg/tooling/`, `pkg/tooling/lsp/`, `extensions/vscode/`, `internal/cli/`, or source maps/debug metadata. Read [implementation/limits](../../documentation/developer-tooling/implementation.md), [tooling architecture](../../pkg/tooling/README.md), and [lessons](../../.experts/tooling-and-docs.md).

- Derive semantics from checked symbols/types and shared traversal. Reuse one source index per request; do not re-lex names for import usage or generate inspection output just to find a receiver.
- Formatting preserves semantics and is idempotent for inline/indented suites, defaults, closures, interpolation, and multiline parameters. Use [ast](../ast/SKILL.md) for changed syntax/recovery.
- Test valid source and incomplete snapshots: preserve neighboring declarations and positions; check navigation/completion with malformed input, LF/CRLF, and relevant Unicode positions.
- Analysis/completion/workspace discovery share nearest-manifest and canonical identity. Confine overlays; malformed nested manifests cannot inherit parent aliases silently. Edits respect versions, shadowing, and binding identity.
- Standard virtual documents are checked source: navigate workspace → stdlib, within stdlib, and across modules, including signature types/hover. Keep documents immutable/outside overlays; register their scheme with the client and test restarts.
- Keep CLI modes, checking, status/output, and native build/run/test paths shared. Source-only commands work without lowering; failed checks preserve outputs. Update command help/examples.
- Preserve source maps, build-level metadata, debugger/DAP behavior, and source-root cache identity. Check native artifacts rather than only generated metadata.
- Run affected tooling/LSP/CLI tests; client changes need extension tests with pinned Node dependencies. Snapshot concurrency needs relevant race checks; debugger changes need native integration. Standalone claims need `make dist-check`.
