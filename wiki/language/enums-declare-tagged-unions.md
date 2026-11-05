[Wiki](../index.md) › [Language](index.md)

# Enums declare tagged unions

Decision (owner, 2026-11-05): replace alternative declarations with `enum`; both payloadless cases and cases carrying data belong to the same construct. Records keep `type`. The later owner direction removes the redundant `case` keyword: enum members are bare names with optional typed payloads, and match arms remain bare. Nominal constructors and exhaustive matching retain their semantics.

Legacy `type` alternatives and `enum` members prefixed with `case` are rejected. The owner requested direct source migration without an automatic syntax fix. Diagnostics explain the required header and prefix changes. `case` becomes an ordinary identifier, including a variant named `case` or `case(value: Int)`. `enum` is reserved. Exported, generic, recursive, and opaque alternatives use the same new keyword, including `export opaque enum`. The internal `Alternative` representation and machine-readable `alternative` classification remain stable. Historical benchmark source snapshots and archived proposals retain the spelling they originally recorded; active programs, fixtures, and documentation use `enum`.

Apply when: writing alternatives or changing declaration parsing, recovery, editor completion, or generated declaration text. Preserve the existing [documentation route](../../documentation/core-language/types/alternatives.md).

Verify: focused enum syntax/recovery and source execution tests, plus `make verify-full`. In generated declarations, enum methods still belong in a separate `impl` block.
