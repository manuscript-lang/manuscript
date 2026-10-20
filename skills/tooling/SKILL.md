---
name: tooling
description: Change Manuscript formatting, lint, inspection, LSP features, VS Code integration, CLI commands, or debugging against checked source.
---

# Tooling

Use for `pkg/tooling/`, `pkg/tooling/lsp/`, `extensions/vscode/`, `internal/cli/`, or source maps/debug metadata. Read [implementation/limits](../../documentation/developer-tooling/implementation.md), [tooling architecture](../../pkg/tooling/README.md), and [lessons](../../.experts/tooling-and-docs.md).

- Derive semantics from checked symbols/types and shared traversal. Reuse one source index per request; do not re-lex names for import usage or generate inspection output just to find a receiver.
- Formatting preserves semantics and is idempotent for inline/indented suites, defaults, closures, interpolation, and multiline parameters. Use [compiler](../compiler/SKILL.md) for changed syntax/recovery.
- Test valid source and incomplete snapshots: preserve neighboring declarations and positions; check navigation/completion with malformed input, LF/CRLF, and relevant Unicode positions.
- Analysis/completion/workspace discovery share nearest-manifest and canonical identity. Confine overlays; malformed nested manifests cannot inherit parent aliases silently. Edits respect versions, shadowing, and binding identity.
- Standard virtual documents are checked source: navigate workspace → stdlib, within stdlib, and across modules, including signature types/hover. Keep documents immutable/outside overlays; register their scheme with the client and test restarts.
- Diagnostics read `<cause>; <fix>`: name the cause, the location, and a concrete fix (nearest name, import line, valid options). Code classification keys on the text before the first `; `, and recovery matches some messages by prefix. Add a hint test for each new message.
- Keep CLI modes, checking, status/output, and native build/run/test paths shared. Source-only commands work without lowering; failed checks preserve outputs. Update command help/examples.
- Preserve source maps, build-level metadata, debugger/DAP behavior, and source-root identity. Check native artifacts rather than only generated metadata. `ms debug` is the scripted, source-level debugger for agents; it resolves names through inspection, not Go symbols.
- The Rust `ms` (`crates/ms-cli`, `ms-tooling`, `ms-lsp`, `ms-guide`) has no `ms debug` and does not implement `ms emit`; `ms profile` replaces the debugger. CLI text, JSON shape, and exit codes are pinned by the conformance corpus, so change both CLIs together until cutover.
- Run affected tooling/LSP/CLI tests; client changes need extension tests with pinned Node dependencies. debugger changes need native integration. Standalone claims need `make dist-check`.
