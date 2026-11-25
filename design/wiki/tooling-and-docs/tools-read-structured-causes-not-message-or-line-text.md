[Wiki](../index.md) › [Tooling and docs](index.md)

# Tools read structured causes, not message or line text

Verified: the driver deduplicated syntax diagnostics by searching messages for " opened at line ", the LSP chose type context by `line.contains("let ")` (which matched `outlet x`, and passed a test only because the trailing space was trimmed), and the task lint and flow view matched import paths and reference names by suffix. Each now reads a fact: `Diagnostic::opener_line`, the cursor line's tokens, the checker's receiver type (`CallSite::spawn`), the exact `@std/concurrency/tasks.ms` import.

Apply when: a tool needs to recognise a diagnostic, call or import. Add a field or ask the checker; do not parse text. Build settings follow the same rule: the build options are parsed from `MS_*` once in `src/cli` (`backend.c`, `pipeline.c`), the layers below read fields, and the cache key hashes the struct, so a new knob cannot be missing from the key.
Evidence: `src/compiler/syntax/diag.h`, `src/cli/backend.c`.
Verify: `ctest --preset ci` and `make conform`.
