# Private fields

## Summary

- Problem: a type is either fully exposed or `opaque`; a record cannot hide one field (a cache, a nonce, an invariant-bearing index) and expose the rest.
- Change: a leading underscore (`_balance`) hides that field or method outside the declaring file (direction from Chinmay, 2026-11-11; replaces a `private` keyword). `opaque type` becomes shorthand for "every field private".
- Decision requested: spelling (`private`), construction rule for private fields, text/JSON form (see Open questions).

## Status

Proposal, 2026-11-11, against `main`. Syntax below is proposed and does not yet pass `ms check`. Nothing is built.

## Problem

Today exporting a type exposes its constructor and every field ([public data surfaces](../documentation/core-language/types/named-types.md#public-data-surfaces)); `export opaque type` hides all of them. Mixed records need a split type:

```text
export type Account:
    id: AccountId
    owner: String
    state: AccountState      # must be an opaque type holding the hidden part
```

- The hidden part needs its own type, accessor functions, and a constructor function, even when it is one field.
- Hidden field types still obey public signature closure, so they cannot stay unexported.
- Callers cannot tell from `Account` which fields are stable API.

## Design

Only the checker and parser change. No runtime or layout change: visibility is a compile-time property of a field.

```text
export type Account:
    id: AccountId
    owner: String
    _balance: Int = 0      # hidden outside the declaring file
    _audit: List[String] = []
```

- Visibility is file-level, matching `opaque` ("declaring file"), not type-level. Methods and `impl` in the same file see everything.
- Outside the file, a private field cannot be read, written, named in a pattern, or passed by name to the constructor. Diagnostic: `field balance is private to account.ms` (same site as today's `opaque_denied`).
- Construction: a private field needs a default to allow construction outside the file; the default fills it. A private field without a default makes the constructor file-only, with today's `it cannot be constructed here`. Positional and named forms both omit private fields.
- Patterns: named destructuring of public fields is allowed; a pattern cannot bind a private field.
- `.clone()`, `==`, and `Hashable` still cover private fields. Skipping them would make equality unsound and clone shallow. Private fields only restrict naming.
- Memory model: no change. One owner, borrow by default, clone as the only copy. A private field cannot be moved or borrowed out by name outside the file, so partial moves ([field-ownership-dataflow](field-ownership-dataflow.md)) stay file-local. Methods named `_x` are file-private the same way (call outside the file is an error). Methods may return a borrow of a private field as any method does.
- Interfaces: operations expose only what their signatures name. An interface cannot require a field, so nothing changes. An `impl` outside the file is still allowed for a type with some public fields; it sees only public ones.
- Public signature closure: private field types need not be exported. A public field whose type is unexported is still rejected.
- `opaque type` keeps its spelling and meaning (all fields private, no outside `impl`, never `Data`); it is not deprecated, since it also forbids outside `impl`.
- `ms api` records `private` per field; adding or changing a private field with a default is compatible, per [software-evolution](software-evolution.md).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | none: privacy is derived from the name; no keyword, no grammar change | none |
| `crates/ms-check` (`exprs.rs`, `calls.rs`, `stmts.rs`, `checker.rs`, `types.rs`) | generalize `opaque_denied` / `opaque_module` from per-type to per-field; defaults fill omitted private fields | `tests/opaque_cases.rs` plus a conformance reject case |
| `crates/ms-lsp`, `ms-tooling` (`guide`, `api`) | completion hides private fields outside file; `ms api` and docs show them | guide and api tests |
| `documentation/core-language/types/named-types.md`, `modules/declarations.md` | replace "no per-field visibility modifiers" | `make docs`, repo-check |
| `wiki/language/` | note the decision | none |

## Alternatives

- Do nothing: the split-type workaround works today but costs a type, accessors and a constructor per hidden group, and has no way to hide a single field with a default. Weakest case against.
- `private` keyword: new grammar and a reserved word; the underscore needs neither. Runner-up if `_` clashes.
- Type-level `private:` block or section: new grammar shape for one bit per field; per-field modifier is smaller.
- Type-scoped (not file-scoped) privacy: needs a new notion of "inside the type" that tests and helpers in the same file would lose. File scope matches `opaque` and needs no new boundary.
- Real runner-up: allow private fields with no default and always generate an outside constructor that omits them. Not possible without a default, since a value must come from somewhere; a file-level `fn new(...)` is the right answer.

## Stages

1. Checker enforcement and diagnostics, `opaque` rewritten as all-private. Check: conformance reject cases, existing opaque tests unchanged.
2. LSP, docs, wiki.

## Open questions

- Leading `_` already marks discarded bindings (`_oldest := remove(...)` in `stdlib/log.ms:327`). Recommend the same rule everywhere: `_name` is hidden from other files and unused-by-design in a local. Check no existing public stdlib field or method starts with `_`.
- Text and JSON form: opaque types print only the type name and are never `Data`. For mixed records, recommend the interpolation form omits private fields and the type is not `Data` outside its file (a private field could otherwise leak through `json.stringify`); inside the file it stays `Data`.
- Should a private field without a default be allowed at all? Recommend yes, with a file-only constructor.
