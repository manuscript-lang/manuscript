[Wiki](../index.md) › [Tooling and docs](index.md)

# Embedded examples are checked by docs-check

Lesson (2026-11-25): after the colon-free types, `=>` and brace-block changes, 45 of 304 embedded `manuscript` examples still used the old syntax, because nothing ran the `manuscript-example` markers. The Rust checker for them was deleted with the Rust implementation and never ported, so a `"mode":"check"` marker checked nothing. The compiler did reject the old syntax; no tool asked it.

`tools/example-check.ms` (part of `docs-check`) now reads every fence in the book, the standard-library descriptions (also fences written in `//` comments), the agent skill, the wiki and the README, and runs `ms check` or `ms test` on it by marker mode. Fragments are wrapped in a function whose parameters are `given`; unused names are allowed, and a fragment without `given` is only parsed. `run` examples are checked, not run.

Apply when: changing syntax, a diagnostic's text that an `error` marker's `contains` names, or a standard-library signature; run `ms run tools/example-check.ms` and fix the examples in the same change. Inline prose such as `` `xs.map(fn x: x)` `` is not covered, so grep for the old spelling.
