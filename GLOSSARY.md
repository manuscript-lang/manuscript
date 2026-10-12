# Manuscript glossary

For definitions and links across the language, see the [plain-language glossary](design/glossary.md).

## Functions and sharing

**Function value**: an ordinary value that may be stored, passed, returned, and invoked concurrently. Closures capture snapshots of bindings. Captured resources can still close while references to them remain.

See [function values and sharing](design/ownership-and-cleanup/values/sharing.md#function-values). The caller chooses whether to run a function concurrently; no separate function kind or sharing proof is needed.
