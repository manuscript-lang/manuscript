# Software evolution

## Summary

- Problem: code changes fast, mostly by agents. After a rename or removal the checker says "unknown name" and guesses the nearest spelling, which is wrong for renames. Nothing tells a library author whether an export change breaks consumers.
- Change: two mechanisms, both compiler output an agent can loop on.
  - **Retirement table:** a removed or renamed name gets a diagnostic that names the replacement and carries a `fix` for `ms check --fix`.
  - **`ms api` diff:** a committed snapshot of a library's exports; `ms verify` fails on a breaking change unless the version was bumped.
- No editions, no new syntax, no manifest level key, no hot reload, no data-compat machinery.
- Cost: one small table in `ms-check`, one `ms api` command, one optional `api.json`.
- Decision requested: approve stages 1 and 2.

## Status

- Proposal, simplified from the first version (merged in #2082) on request: "can we simplify". 2026-10-31.
- Direction (Chinmay): "we need a way to handle software evolution in manuscript ... how would you design this for agents and human world that's gonna change rapidly".
- Rules: Manuscript first, Linux/macOS/Windows parity.
- Not run: no `ms` was built, so CLI output shapes are illustrative.

## Problem

Verified:

- `ms check --fix` applies `fix` edits for misspellings and habits (`documentation/developer-tooling/source/diagnostics.md`). No fix encodes "renamed in release N".
- `documentation/contributing/maintenance.md` ("Public compatibility") requires deprecations to document the replacement and removal release and to test both. No tool checks it.
- Third-party packages are unsupported (`project-configuration.md`), so the consumers that matter are in-repo projects and copied libraries.
- `ms inspect` has symbols but no export-only view and no diff.

Non-goals: editions, hot reload, a package manager, compatibility shims.

## Design

### 1. Retirement table

- When a stdlib export or language construct is renamed or removed, `ms-check` keeps one table entry: old name, replacement, release removed.
- Diagnostic follows the existing shape: `'json.decode' was renamed to 'json.parse' in 0.4; use 'json.parse'`.
- It carries a `fix` replacing the old name, so `ms check --fix` migrates it. Entries with no mechanical replacement are prose only.
- JSON adds optional `removed_in` beside `subcode`. Consumers already tolerate absent optional fields.
- Entries are deleted after three minors; the name then falls back to the ordinary unknown-name error.
- Each entry needs a conformance fixture (old spelling in, diagnostic and fix out), which satisfies the "tests both" rule.
- A rename PR is: change the stdlib, add the entry, add the fixture.

### 2. `ms api` and `ms verify`

`ms api <ms.toml> [-o api.json]` writes the exported surface of a library project: per export, kind, parameters with defaults, result, record fields with defaults, alternative cases, interface operations, and whether the type is `opaque`. Output is sorted and LF, so it is identical on all platforms. It filters the checked metadata `ms inspect` already computes; public signature closure guarantees every type a signature names is in the surface.

`ms api diff old.json new.json` classifies changes by Manuscript's own rules:

| Change | Class |
| --- | --- |
| Export removed or renamed; parameter or result type changed | breaking |
| Parameter or record field added without default | breaking |
| Case added to exported alternative (callers' exhaustive `match` fails) | breaking |
| Operation added to exported `interface` | breaking |
| Parameter or field added with default; change inside `export opaque type` | compatible |
| New export | additive |

- Each result row has `class`, `symbol`, `before`, `after`.
- Exit 0 for compatible or additive, 1 for breaking.
- `ms verify` diffs the project against a committed `api.json`. A breaking diff fails unless `[project] version` (checked with `@std/semver`) was bumped per `maintenance.md`: minor before 1.0, major after. `ms api -o api.json` re-baselines.
- The diff classifier is Manuscript in `stdlib/` over `@std/json`; Rust only emits the surface.

### Dropped from the first version

- `ms = "0.x"` level key: nothing depends on it without editions.
- `Deprecated(...)` comment grammar: a plain rename is a table entry, and an in-repo deprecation is a normal doc comment.
- Persisted-data corpus helper: an ordinary test that calls `json.parse[T]` on committed sample files already does this, with no new API. Documented as advice only.
- Hot reload: stays out; services roll over with a new binary, using existing cancellation and cleanup.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` | retirement table, `removed_in` on diagnostics | conformance fixture per entry |
| `crates/ms-cli` | `ms api`, `ms api diff`, `ms verify` hook | `snippets/cli/` fixtures |
| `stdlib/*.ms` | diff classifier module | stdlib e2e fixture per table row |
| `ms-syntax`, `ms-lower`, `ms-rt`, codegen, formatter | unchanged | n/a |
| `ms.toml` | optional `version` in `[project]` | manifest accept and reject fixtures |
| Docs, wiki | diagnostics page, `maintenance.md`, one wiki page | doc fences |

## Alternatives

- Do nothing: renames keep producing misleading nearest-name hints.
- First version of this proposal: also had a level key, deprecation grammar, and data helper; each added surface without a current consumer.
- Editions: fork semantics; wrong while pre-1.0 removals are allowed.
- Diff in Rust: the classifier is data logic the stdlib can host.

## Staging and verification

1. Retirement table, `--fix`, fixtures. Gate: one real past rename covered; `make conform` green on all platforms.
2. `ms api`, `ms api diff`, `ms verify`. Gate: output byte-identical on Linux, macOS, Windows; a library fixture fails on an unbumped breaking change.

## Open questions

1. Retirement window: three minors (recommended) or one.
2. Stale `api.json`: fail (recommended for libraries with consumers) or warn.
