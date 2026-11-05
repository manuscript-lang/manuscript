# Enum declarations

## Summary

- Declare tagged unions with `enum`; records keep `type`.
- Payloadless cases and cases carrying data share the same construct.
- Preserve nominal constructors, exhaustive matching, ownership, and runtime representation.

## Status

Implemented, 2026-11-05, against `5f6b8c3a2`. Owner direction: “okay lets change it to enum, once done create and merge pr”. Independent skeptical proposal and implementation reviews approved the design after correcting three generated test sources.

## Decisions

- Replace legacy case-containing `type` declarations rather than support two spellings during alpha; diagnose them with an exact keyword repair usable by `ms check --fix`.
- Preserve generics, recursive types, and `export`, `opaque`, and `export opaque` modifiers on enums.
- Reserve `enum`; existing identifiers with that name must be renamed.
- Enums contain one or more cases; fields belong to `type`, methods to `impl`.
- Keep the internal `Alternative` AST/HIR and machine-readable `alternative` classification stable; rendered declarations and editor symbols identify enums.
- Preserve the existing `alternatives.md` documentation route while teaching enums.
- Canonical syntax and migration guidance live in [Enums](../documentation/core-language/types/alternatives.md); the durable decision lives in the [wiki](../wiki/language/enums-declare-tagged-unions.md).
