[Wiki](../index.md) › [Language](index.md)

# Optional chaining `?.` is for Optionals only

Decision (Chinmay, 2026-11-14): `?.` stays an Optional-only operator. Do not extend it to Results or errors, or add a second chaining form; propagate failures with `?` and handle them with `match`.

Apply when: designing or changing `?.`, `?`, or Optional and Result syntax.
Evidence: [language-design](../../skills/language-design/SKILL.md).
