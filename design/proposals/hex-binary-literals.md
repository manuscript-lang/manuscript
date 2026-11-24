# Hex and binary integer literals, digit separators

## Summary

- Problem: masks, colors and protocol constants must be written in decimal (`16711680` for `0xFF0000`), and long numbers have no grouping.
- Change: `0x` and `0b` integer literals, and `_` between digits of integer and float literals. No octal, no uppercase prefixes, no hex floats, no BigInt suffix.
- Value rules: a hex or binary literal is a value that must fit signed 64-bit like a decimal one; sized-int contexts use the existing range rules.
- Scope: lexer, literal value parsing (check and lower share `ms_syntax::number::canonical`), docs, conformance fixtures. The formatter prints literals as written.

## Status

- **Approved** by Chinmay on 2026-10-25 (`0x`, `0b`, `_`; no octal). Spec: G11 in the data-types review.

## Alternatives

- Do nothing: keeps one decimal spelling but hides bit structure.
- Allow octal and uppercase prefixes: more spellings for little use.
