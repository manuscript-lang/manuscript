[Wiki](../index.md) › [Language](index.md)

# A `Char` type is deferred until after the release

Decision (Chinmay, 2026-11-18): `Char` is not rejected, only deferred. Until after the release, characters are handled as `Int` (`scalar_values()`, `scalar_at`, the `@std/unicode` predicates), and the change is scheduled for a revisit after it.

The design write-up recommended adding it: one Unicode scalar value, 4 bytes, copied like an `Int`, a `'a'` literal, `chars()` yielding `Char` lazily, `from_chars` that cannot fail, and removal of `scalar_at`, `scalar_values`, `from_scalars` and the `Int` predicates. Grapheme clusters stay out of the type system, and there is no `find_byte`.
- The reason is readability and safety, not speed: plain `chars()` loops are already fast (the compiler fuses them), and the slow shape is only a predicate that takes a one-character `String` (3.0 ns per byte against 0.73 with an `Int` predicate, #4076).
- The cost is one large mechanical PR (about 300 call sites plus checker, lowering, formatter, LSP, docs, the bundled skill and fixtures) and a grammar change that needs the owner's approval.
- Without the type, an API is added only when existing features cannot cover the need; code with and without the change is how a decision is shown.

Apply when: proposing `Char`, a single-quote literal, or a char-specific API; revisit after the release.
Evidence: design write-up `char-type-2026-11-18.md` in the project files (not in the repo).
Verify: nothing adds a `Char` type or `'a'` literal before the release without the owner's approval.
