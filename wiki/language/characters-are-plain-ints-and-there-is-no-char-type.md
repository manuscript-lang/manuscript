[Wiki](../index.md) › [Language](index.md)

# Characters are plain `Int` values; there is no `Char` type

Decision (Chinmay, 2026-11-18): code points are handled as `Int`. Do not add a `Char` type or a char-specific API before the release; revisit only afterwards.

An API is added only when existing features cannot cover the need. Chars already give a plain `Int`, so a new type has to show a concrete problem that `Int` leaves unsolved, with a program written with and without the change.

Apply when: proposing a character type, a char literal API, or any new type that wraps an existing scalar.
Verify: the proposal includes the with and without programs, and shows what `Int` cannot do.
