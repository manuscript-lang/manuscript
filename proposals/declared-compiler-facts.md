# Declared compiler facts instead of name tests

## Summary

- Problem: the checker and lowering decided behavior by spelling: native identity encoded in a
  string, diagnostics matched by message text, runtime facts by symbol prefix, primitives and time
  types by id text, `none`/`caller_site` by the name written.
- Change: each fact is declared once (a resolution, a `Cause`, a runtime `// ms:` flag, a `Native`
  or `Builtin` tag) and every consumer reads it. Where a name must still be matched (the time
  types, `caller_site`, `core/panic`, the `Decimal` layout) it is matched in one place.
- Decision requested: none; no syntax. Visible changes: a program's own `caller_site` or `none`
  is no longer read as the library default, and a bad shift count panics from `math.ms`.

## Status

Implemented 2026-11-09 against `f2cc2461`. Covers the first sweep of the compiler hacks audit
(N1, N2, N5 to N8, N10 to N12). N9 waits on the trim/split and close work; the second sweep
(N13 to N20) is proposal-sized and follows separately. Skeptical review: ship with changes;
applied (file domains corrected, flag parameters checked at build time, tests added).

## Problem

```ms
fn caller_site() Int:
    return 5

fn site(value: Int = caller_site()) Int:
    return value
```

`site()` was lowered as the test library's call-site default, by name
(`tests/e2e/testdata/accept/defaults-by-resolution.ms`).

- Rewording a diagnostic changed which diagnostics were emitted: inference tested earlier
  messages with `starts_with("cannot infer ...")` and `message == "unknown binding X"`.
- A local named `none` or `caller_site` was read as the default form of that name.
- `extern_role` treated any symbol containing `_serve` as a task spawner; `domain_of` mapped 28
  symbol prefixes to an error domain; `method_symbol` assembled runtime names with renames.
- `Sym.native` was `""`, `"contract"`, `"extern:<sym>"` or `"module/name"`, tested 62 times by
  spelling; bundled versus user externs were told apart by the `@std/` path prefix.
- `lower_ty`, JSON codegen and integer width tests dispatched on `"Int"`, `"UInt64"` and so on;
  time types on `(module, name)` at each use; Bool exhaustiveness on `seen.len() == 2`.
- The checker kept its own lists of callback-keeping and value-taking externs, duplicating the
  runtime's declarations (a test kept them in sync).

## Design

One rule: a fact is declared where the thing is defined, and every consumer reads the declaration.

- `Diagnostic.cause: Cause` (`CannotInfer`, `CannotInferCallback`, `Mismatch`, `Unknown(name)`,
  `UnknownMember`) is set by the reporter; inference and suppression match on it.
- Defaults are classified by resolution: `ModuleData::default_form` returns `None`,
  `CallerSite` or `Expr` from what the default expression resolved to.
- Runtime functions declare `op=<mnemonic>` (one MIR instruction), `spawns`, `takes:<param>`,
  `keeps:<param>` and a file-level `//! ms: domain <words>` (per-function `domain=` overrides).
  `cargo xtask symbols` writes them to `rt_symbols.txt`; lowering and the checker read the table.
- `enum Native { Source, Contract, Extern { symbol, bundled }, Builtin(Name) }` on `Sym`,
  `Method` and `Info`. `bundled` is set when an embedded standard module declares the extern.
- `Builtin` gains the primitive types and `Timestamp`, `Instant`, `Duration`; the primitive tag is
  set when the type is made, the time tags when `@std/time.ms` registers its records.
- `Self` is `Builtin::SelfType`; derived `hash` requires `Builtin::Hashable`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` diag | `Cause` on `Diagnostic` | checker golden diagnostics |
| `ms-check` | `Native`, `Builtin` prims and time, `default_form`, causes, runtime facts from `rt_symbols.txt` | `cargo test -p ms-check`, conformance |
| `ms-lower` | reads `Native`, `Builtin`, flags; `domain_of` and renames deleted | conformance run/test phases |
| `ms-rt`, `ms-std-*` | `// ms:` flags and `//! ms: domain` | `cargo xtask symbols` diff |
| `stdlib/*.ms` | shifts check their count in Manuscript; HTTP method passed as text | conformance |
| `xtask` | accepts the new flags | xtask tests |

## Alternatives

- Do nothing: each new runtime function, message rewording or local name risks a silent change;
  the audit found 62 identity tests and 28 prefixes that had to be kept in step by hand.
- Tag only the semantic sites (N10, N6): leaves the runtime tables and identity strings, which are
  the bulk of the drift risk.
- A new `pod`/`consuming` declaration syntax for `Decimal` layout and `build`: a language change;
  deferred to Chinmay with N9.
