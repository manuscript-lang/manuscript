[Wiki](../index.md) › [Language](index.md)

# Enums declare tagged unions

Decision (owner, 2026-11-05): replace alternative declarations with `enum`; both payloadless cases and cases carrying data belong to the same construct. Records keep `type`. This is a syntax migration, with the existing nominal constructors and exhaustive matching semantics.

Legacy `type` declarations containing cases are rejected with a machine-applicable keyword replacement. `enum` is reserved. Exported, generic, recursive, and opaque alternatives use the same new keyword, including `export opaque enum`. The internal `Alternative` representation and machine-readable `alternative` classification remain stable. Historical benchmark source snapshots and archived proposals retain the spelling they originally recorded; active programs, fixtures, and documentation use `enum`.

Apply when: writing alternatives or changing declaration parsing, recovery, editor completion, or generated declaration text. Preserve the existing [documentation route](../../documentation/core-language/types/alternatives.md).

Verify: focused enum syntax/recovery and source execution tests, plus `make verify-full`. In generated declarations, enum methods still belong in a separate `impl` block.
