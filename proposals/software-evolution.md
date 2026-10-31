# Software evolution: language, packages, data

## Summary

- Problem: code changes fast and mostly by agents; Manuscript has pieces (`--fix`, public-signature closure, `ms inspect`) but no end-to-end loop for "what broke, is it safe, how do I migrate".
- Change: one rule, **every incompatible change ships with a machine-readable migration and a frozen before/after fixture**. Three mechanisms: retired-name diagnostics with fixes (language/stdlib), `ms api` surface snapshots and diffs (projects and future packages), compatibility fixtures for persisted data (services).
- No editions, no new syntax, no in-process hot reload. Rust additions are limited to an API-surface emitter reusing `ms inspect`; classification and diff logic is Manuscript in `stdlib/`.
- Cost: a committed `api.json` per library project, a `ms = "0.x"` manifest key, and diagnostic metadata fields.
- Decision requested: approve stages 1 to 3 below and answer the open questions.

## Status

- Proposal. 2026-10-31. Checked against the `claude/project-thread-c0brpm` checkout (main at session start).
- Direction (Chinmay): "we need a way to handle software evolution in manuscript, where the code can potentially change, how would you design this for agents and human world that's gonna change rapidly". Project rules: Manuscript first, Linux/macOS/Windows parity.
- Not run: no `ms` binary was built in this session, so `.ms` snippets reuse documented syntax only and the new CLI output shapes are illustrative.

## Problem

Verified current state:

- `ms check --fix` / `ms lint --fix` apply `fix` edits (`documentation/developer-tooling/source/diagnostics.md`). Fixes cover misspellings, habits, conversions. None encodes "this API was renamed in release N".
- `documentation/contributing/maintenance.md` ("Public compatibility") requires that a deprecation documents the replacement and removal release and tests both, but no tool reads or enforces that. Pre-1.0 incompatible changes go in minors.
- `.msversion` (`0.1.0`) versions the toolchain; `ms.toml` has only `[project]` and `[aliases]` and cannot say which `ms` a project targets. Unknown keys are rejected, so adding one is a deliberate manifest change.
- Third-party packages are unsupported; sharing is copying sources (`project-configuration.md`). So "package evolution" today means a library project and its in-repo consumers, and later a package manager.
- `ms inspect` emits symbols and source hashes as JSON, but there is no exported-surface view and no diff.
- `stdlib/json.ms` `parse` ignores unknown fields by default (`ignore_unknown_fields: Bool = true`); there is no check that persisted data written by old code still decodes.
- Wiki lesson "Removing a construct includes its surrounding APIs": removals already require sweeping helpers, docs, and tests. This is manual.

Non-goals:

- Editions (parallel language semantics selected per project).
- In-process hot code reload.
- A package registry or dependency solver (this design must compose with one).
- Source-level compatibility shims that keep retired syntax parsing.

## Design

### 1. Principle

Agents recover from change only if the change is announced by the compiler as data. So: the compiler is the migration channel. Prose in release notes is secondary.

### 2. Language and standard-library evolution

**Targeted level.** `ms.toml` gains an optional key:

```toml
[project]
name = "store"
source = "./src"
ms = "0.4"
```

- `ms` is a `major.minor` level (pre-1.0: minor). Absent means "current toolchain", so existing projects are unaffected.
- A toolchain older than the level fails with a diagnostic naming the required release. A newer toolchain checks normally and reports retired names (below). It never reinterprets semantics by level: one language, no editions. The level only decides which migrations are pending.
- Hypothesis: a level key is enough, because the policy is "remove, don't fork"; if two incompatible semantics must coexist, that is an edition and needs its own proposal.

**Retired-name diagnostics.** When a construct or stdlib export is removed or renamed, the checker keeps a retirement entry instead of silently failing as "unknown name":

- Entry fields: `subcode` (never reused, as for existing subcodes), `since`, `removed_in`, `replacement` (text), `fix` kind (`rename`, `call-shape`, or `prose`).
- Message follows the existing `<cause>; <fix>` shape: `'json.decode' was removed in 0.4; use 'json.parse'`.
- `--json` adds optional `retired: {since, removed_in}` next to `subcode`/`fix`. Consumers already tolerate absent optional fields.
- `ms check --fix` applies `rename` and `call-shape` fixes. `prose` entries stay manual and are listed.
- Entries live for N minors (default 3), then are deleted. After deletion the name is a plain unknown-name error, which the existing nearest-name suggester handles.

**Deprecation of stdlib APIs, no new syntax.** Stdlib docs live in `stdlib/*.ms` comments. A deprecation is one reserved comment line directly above the declaration:

```manuscript
# Deprecated(0.4, remove 0.7): use parse.
export fn decode(text: String) JsonValue!JsonError:
    return parse(text)
```

- The checker parses the line (exact grammar, rejected if malformed) and emits a warning with `retired` metadata plus a `rename` fix when the replacement is a single exported name with the same signature.
- A comment convention avoids an attribute system. If review prefers a real marker, that is a language change (open question 1).
- `ms-repo-check` fails if a stdlib export is deprecated without a conformance fixture covering the warning and the fix, enforcing the existing "tests both" rule.

**Migration is a rule table, not scripts.** Codemods are the `fix` edits above. Anything beyond rename and call-shape (semantic changes) is prose in `ms guide <subcode>` and stays a human or agent edit guided by diagnostics. This bounds the Rust surface: one retirement table consumer in `ms-check`, entries are data.

**Per-change checklist (replaces ad hoc practice):** each breaking change PR adds (a) a retirement entry or deprecation line, (b) a conformance fixture pair `before` (old spelling, expects the retired diagnostic and fix) and `after` (fixed output, expects clean), (c) a wiki line if a decision was made.

### 3. Package and project API evolution

**`ms api <ms.toml> [-o api.json]`** emits the exported surface of a library project, deterministic and platform-independent (sorted, LF, relative paths):

```json
{
  "format": 1,
  "project": "graph",
  "version": "0.3.1",
  "exports": [
    {"module": "src/graph.ms", "name": "Edge", "kind": "record", "opaque": false,
     "fields": [{"name": "from", "type": "Int"}, {"name": "weight", "type": "Float", "default": true}]},
    {"module": "src/graph.ms", "name": "shortest", "kind": "fn",
     "params": [{"name": "g", "type": "Graph"}, {"name": "from", "type": "Int"}],
     "result": "Path?"}
  ]
}
```

- It is a projection of the checked metadata `ms inspect` already computes, filtered by `export`. Public signature closure (documented in `documentation/core-language/modules/declarations.md`) guarantees that every type a signature names is itself in the surface.
- `version` comes from a new optional `[project] version = "x.y.z"`, validated with `@std/semver`.

**`ms api diff old.json new.json [--json]`** classifies each change. The classifier is Manuscript in `stdlib/` (data in, data out, using `@std/json` and `@std/semver`), invoked by a thin CLI wrapper:

| Change | Class | Reason (Manuscript-specific) |
| --- | --- | --- |
| Export removed or renamed | breaking | imports are by name |
| Parameter type, order, or result changed | breaking | |
| Parameter added without default | breaking | callers omit it |
| Parameter added with default | compatible | defaults exist |
| Field added to exported record without default | breaking | exporting a record exposes its constructor and every field |
| Field added with default | compatible | |
| Case added to exported alternative | breaking | callers' exhaustive `match` fails to check |
| Operation added to exported `interface` | breaking | implementors lack it |
| Anything inside `export opaque type` | compatible | representation hidden outside the file |
| New export | additive | needs minor bump |

- Output per change: `class`, `symbol`, `before`, `after`, `consumer_effect` (one sentence), and `suggest`: for example "make the type `opaque`" or "add a default".
- Exit status: 0 compatible/additive only, 1 breaking, 2 error.

**Enforcement in `ms verify`.** If `api.json` is committed beside `ms.toml`, `ms verify` regenerates the surface and diffs against it. A mismatch is a failure unless `[project] version` was bumped to the required level (breaking: minor pre-1.0, major from 1.0; additive: patch pre-1.0, minor from 1.0), matching `maintenance.md`. `ms api -o api.json` re-baselines. Agents get a closed loop: change code, `ms verify` says "breaking, bump version or restore", they decide.

**Consumers.** Until a package manager exists, consumers hold copied sources. A copy records its `api.json` hash in the consumer's own notes (existing practice records revision and checksums). When updating a copy, `ms api diff` between the old and new baselines lists exactly which consumer call sites to re-check, and normal `ms check` finds them. When a package manager is designed, `version` and `api.json` are the inputs for its compatibility check; this proposal does not decide its lockfile.

### 4. Data and long-running services

**Persisted data compatibility.**

- Rule: a type that is persisted (JSON, files, queues) gets a committed *compat corpus*: encoded samples from each released shape, under `testdata/compat/<Type>/<version>.json`.
- `@std/test` gains a helper written in Manuscript (stdlib, no Rust) that, for a given type and directory, parses every sample with `json.parse[T]` and reports the file and cause of the first failure. Used as an ordinary test; no new runner.
- Evolution rules, documented and enforced by `ms api diff` for types marked persisted by the project (a list in `api.json` generation config; open question 3):
  - adding a field with a default: compatible both ways;
  - adding a field without default: breaking for old data;
  - removing or renaming a field: breaking for old data, compatible for old readers only because `ignore_unknown_fields` defaults to true (verified in `stdlib/json.ms`);
  - adding an alternative case: old readers fail on new data.
- Because decoding is typed (`parse[T]`), a schema change is a compile-time `api diff` event plus a runtime corpus failure, never silent.

**Long-running services.**

- Position: no in-process hot reload. Manuscript compiles to native executables with value semantics and scoped cleanup; patching live code would need a stable state layout across versions, which the compiler does not promise. Not evidence-tested; stated as a design choice with this reason.
- Evolution path is rolling replacement: start new binary, drain old, using existing structured cancellation and cleanup so in-flight work finishes or cancels at known points.
- What the language adds: the compat corpus above covers mixed-version fleets (new writers, old readers, and the reverse). Anything stronger (state handoff between versions) is out of scope.
- `crates/ms-rt-hot` is unrelated: it is inlined runtime helpers, not code reload. Its name may confuse; rename is out of scope.

### 5. Agent contract

Everything above is data an agent can loop on without reading prose:

```text
ms verify --json        # diagnostics incl. retired + fix, api diff status
ms check --fix          # apply rename/call-shape migrations
ms api diff a.json b.json --json
ms guide MS2002.4       # explains a retired-name subcode
```

- Stable keys: `code`, `subcode`, `retired`, `fix`, `class`, `symbol`.
- Compiler-enforced guarantees: unknown manifest keys rejected; stale `api.json` fails verify; deprecations without fixtures fail repo-check.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | none (no new syntax) | n/a |
| `crates/ms-check` | retirement table consumer; parse reserved `Deprecated(...)` comment; `retired` and `subcode` on diagnostics | conformance `before`/`after` pairs |
| `crates/ms-driver` | accept `ms` and `version` in `[project]`; level check | manifest accept/reject fixtures |
| `crates/ms-tooling` / `ms-cli` | `ms api`, `ms api diff` wrappers; `ms verify` integration; `ms guide` for new subcodes | `snippets/cli/` fixtures, exit codes |
| `stdlib/*.ms` | diff classifier module; compat-corpus test helper; deprecation comments | stdlib e2e fixtures |
| `crates/ms-repo-check` | deprecation-needs-fixture rule | repo-check unit test |
| `crates/ms-lower`, `ms-rt`, codegen | unchanged | n/a |
| Formatter, LSP, VS Code | LSP shows `retired` diagnostics with the existing quick-fix path; formatter unchanged | LSP diagnostic test |
| Docs/wiki | project-configuration keys; diagnostics `retired`; `maintenance.md` points at tooling; wiki page on evolution rules | doc fences via conformance |

## Alternatives

- Do nothing. Maintenance policy exists but is manual; agents get "unknown name" with a nearest-name guess, which misleads on renames (the right answer is the new name, not the most similar old one). Cost grows with change rate.
- Editions. Gives long compatibility but forks semantics, multiplies the conformance corpus, and suits a stable language. Pre-1.0 with a "remove after N minors" policy is cheaper. Revisit at 1.0.
- Attribute/annotation syntax for `deprecated`. Cleaner than a comment but is a language addition for one feature; the comment is checkable and replaceable later.
- Diff in Rust only. Smaller to write once, but the classifier is exactly the kind of data logic stdlib is meant to host, and it must also work on baselines produced by other versions.
- Hot reload. Rejected above; rolling replacement meets the stated need.
- Smallest version: stage 1 only (retirement diagnostics) delivers most agent value for the language itself.

## Staging and verification

1. **Retirement diagnostics.** Table, `retired` JSON, `--fix` for renames, `Deprecated(...)` parsing, repo-check rule. Gate: a real past rename gets a fixture pair; `make conform` green on all three platforms.
2. **`ms api` and `ms api diff`.** Emitter plus Manuscript classifier; diff table covered by one fixture per row. Gate: output byte-identical on Linux, macOS, Windows.
3. **`ms verify` enforcement and `[project] ms`/`version`.** Gate: a library fixture fails on unbumped breaking change.
4. **Compat corpus helper and docs.** Gate: a persisted-type fixture fails on a removed field.

Each stage lands green under `make verify`; none disables any platform's tests.

## Open questions

1. Deprecation marker: reserved comment line (recommended, no language change) or a real attribute syntax.
2. Retirement window: three minors pre-1.0 (recommended) or one.
3. Which types count as persisted: explicit list in `ms.toml` (recommended, e.g. `persisted = ["Edge"]`) or inferred from use with `json.parse`/`stringify`.
4. Should `ms verify` fail or warn on a stale `api.json` when the project has no consumers outside the repo.
