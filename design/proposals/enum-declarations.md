# Enum declarations

## Summary

- Declare tagged unions with `enum`; records keep `type`.
- Enum members are bare variant names, optionally followed by typed payload parameters.
- Remove the redundant `case` keyword while preserving constructors and exhaustive matching.

## Status

Approved by the owner, 2026-11-05: “we can get rid of case keyword as well, that’s redundant now”. The later direction asks to migrate existing sources directly, without adding a syntax autofix.

## Problem

- `enum Outcome:` already establishes that its body declares alternatives.
- Prefixing every variant with `case` repeats that information.
- Match arms already use bare names; constructors and matching need no new representation.

## Design

- Write `enum Outcome[T = Int]:` with `Success(value: T)` and `Failure` members.
- Require one or more variants; reject enum fields, defaults, method declarations, and ellipsis bodies.
- Keep `export enum`, `opaque enum`, and `export opaque enum`, including generics and recursive payloads.
- Keep payloadless variants as values and payload variants as existing constructor calls.
- Keep existing nominal identity, type argument inference, exhaustive matching, ownership, and layout.
- Keep match arms bare; this changes declarations, not pattern syntax.
- Remove `case` from the token and reserved-word sets.
- Permit `case` as an ordinary identifier: a field, parameter, local, function, or variant name.
- A variant named `case` is written `case` or `case(value: Int)`; it is not a second declaration form.
- Resolve lowercase arms from the matched type: Optional payload binding or payloadless enum variant, with no synthetic binding for the latter.
- Recognize legacy `case Name` only when the extra name proves a redundant prefix.
- Reject legacy prefixes and `type` alternatives with clear diagnostics, without automatic migration fixes.
- Preserve the existing legacy match-arm diagnostic; arms remain bare.
- Migrate repository sources directly, retaining current main's teaching and ownership improvements.
- Keep only one accepted enum spelling; migration diagnostics do not accept old syntax.
- Keep internal `Alternative`/`Case` representations and machine-readable classifications stable.
- Migrate active stdlib, programs, examples, fixtures, current documentation, and generated declaration text.
- Preserve historical benchmark snapshots and archived proposals; they remain evidence of their original revision.
- Keep the unrelated n-body correction unpublished.

## Components touched

| Component | Change | Verification |
| --- | --- | --- |
| `ms-syntax` | Bare members, contextual legacy diagnostics, keyword removal | strict, recovery, LF/CRLF, formatter, identifier regressions |
| `ms-check` | Keep variant semantics and distinguish lowercase variants from Optional bindings | checker corpus, native execution, and conformance |
| `ms-tooling` | Bare generated variants and current guide syntax | API, docs, and book checks |
| `ms-lsp` | Bare-variant discovery, snippets, tokens, recovery | identity, completion, semantic, and navigation tests |
| VS Code grammar | Bare variant scopes; ordinary `case` identifiers | highlighting and extension package |
| Stdlib and fixtures | Remove redundant member prefixes | complete conformance and native e2e |

## Alternatives

- Keep `case`: rejected by the owner's later explicit direction.
- Accept both: retains redundant syntax; diagnose legacy syntax instead.
- Keep `case` reserved without using it: needlessly prevents ordinary identifiers.
- Rename representations or add a second payloadless facility: adds unrelated machinery.

## Verification

- Independent skeptical review before implementation and an independent final diff review.
- Focused legacy rejection, member-shape, identifier, recovery, tooling, and native execution regressions.
- Full applicable aggregate checks and exact-head required CI before normal merge.
- Disclose the pre-existing n-body aggregate failure while retaining the requested scope.
