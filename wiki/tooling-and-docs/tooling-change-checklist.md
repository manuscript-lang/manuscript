[Wiki](../index.md) › [Tooling and docs](index.md)

# Tooling change checklist

Verified: rules gathered from past formatter, LSP, CLI, and diagnostics work; the linked lessons carry the evidence.

Apply when: changing `ms-tooling`, `ms-lsp`, `ms-cli`, `extensions/vscode/`, line tables, or profiling.

Use for `crates/ms-tooling`, `ms-lsp`, `ms-cli`, `extensions/vscode/`, or line tables/profiling. Read [implementation/limits](../../documentation/developer-tooling/implementation.md) and [lessons](../tooling-and-docs/index.md).

- Derive semantics from checked symbols/types and shared traversal. Reuse one source index per request; do not re-lex names for import usage or generate inspection output just to find a receiver.
- A formatter change that rewraps existing code reformats the repo (`ms fmt stdlib tests tools`; `reject` fixtures stay unparsable) and needs `UPDATE_SNAPSHOTS=1 cargo test -p ms-lsp --test snapshots`, since navigation snapshots hold stdlib positions. `ms fmt` wraps bare imports over the width into `import (...)`.
- Formatting preserves semantics and is idempotent for inline/indented suites, defaults, closures, interpolation, and multiline parameters. Use the [compiler checklist](../compiler/compiler-change-checklist.md) for changed syntax/recovery.
- Test valid source and incomplete snapshots: preserve neighboring declarations and positions; check navigation/completion with malformed input, LF/CRLF, and relevant Unicode positions.
- Analysis/completion/workspace discovery share nearest-manifest and canonical identity. Confine overlays; malformed nested manifests cannot inherit parent aliases silently. Edits respect versions, shadowing, and binding identity.
- Standard virtual documents are checked source: navigate workspace → stdlib, within stdlib, and across modules, including signature types/hover. Keep documents immutable/outside overlays; register their scheme with the client and test restarts.
- Diagnostics read `<cause>; <fix>`: name the cause, the location, and a concrete fix (nearest name, import line, valid options). Code classification keys on the text before the first `; `, and recovery matches some messages by prefix. Add a hint test for each new message.
- `ms check` and `ms lint` take `--fix` to apply machine-applicable fixes (the `fix` field of `--json` diagnostics: misspellings, missing imports, `let`→`var`, `Some`/`Ok`/`true` habits, `Case()` parentheses, Int→Float and →String conversions, `.clone()`); `ms guide <code>` describes a diagnostic code; `ms run` and `ms test` take `--json` and report a runtime fault as structured data. Diagnostics name the Manuscript replacement for habits from TypeScript, Go and Rust (`unwrap`, `len`, `for (...)`, `Int("1")`), and any camelCase member maps to its snake_case one.
- Keep CLI modes, checking, status/output, and native build/run/test paths shared. Source-only commands work without lowering; failed checks preserve outputs. Update command help/examples.
- Native builds emit DWARF line tables and `app.ms-build.json`; `ms profile` provides folded stacks, pprof, and a top report. Check native artifacts rather than only metadata. There is no `ms debug` or `ms emit`.
- CLI text, JSON shape, and exit codes are pinned by the conformance corpus (`make conform`); update `tests/conformance/` expectations deliberately.
- Run affected crate tests (`cargo nextest run -p ms-tooling` etc.); client changes need extension tests with pinned Node dependencies. Standalone claims need `make dist-check`.
