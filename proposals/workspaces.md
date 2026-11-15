# Workspaces and per-package compile

## Summary

- Problem: a project is one `ms.toml` at one root; code cannot be split into packages inside one repository, and every `ms build` redoes all codegen after any edit.
- Change: a root `ms.toml` with `[workspace] members`, path dependencies between members, one `ms.lock`; then a per-package object cache so an unchanged package is not recompiled.
- Decision requested: approve the manifest shape (user-visible) and the staging; stage 3 (cache) goes ahead only if its spike meets the gate below.

## Status

Proposal, 2026-11-15, checked against `046790d5`. Direction (Chinmay): "workspaces, and a way of organizing code and speeding up compile with packages". Builds on `proposals/packages.md` (git dependencies, effects) and the parked checking cache in `proposals/incremental-builds.md`. The packages thread owns the dependency table, `ms add/install/remove` and the resolver (`/mnt/project-files/packages/package-resolution.md`); this proposal adds to them and waits for manuscript#4090.

## Problem

- `read_project` takes one manifest; `confinement_root` rejects imports that leave the project root, so a sibling directory cannot be a package.
- A second `ms build` after a one-line edit repeats everything. Measured (release `ms`, `046790d5`, 4 cores, 40 directories x 25 files, 122k lines from the old compile-time generator, ported to current syntax, `MS_CACHE=off`):

| Step | Time |
| --- | --- |
| `ms check` | 1.73 s |
| `ms build --build-type Debug`, warm (check + lower 2.2 s, MIR optimize 0.2 s, Cranelift codegen 2.1 s, link 0.07 s) | 4.7 s |
| `ms build` Release | 37.7 s |

- The existing build cache (`crates/ms-build/src/cache.rs`) skips a no-change rebuild (0.02 s) but any edit invalidates all of it.

## Design

**Manifest.** The root `ms.toml` lists members; each member has its own `ms.toml` with `[project]`.

```toml
# ms.toml at the repository root
[workspace]
members = ["app", "libs/*"]
```

```toml
# app/ms.toml
[project]
name = "app"
source = "./src"
entry = "./src/main.ms"

[dependencies]
"@util" = { path = "../libs/util" }
"@pg" = { url = "https://github.com/acme/pg.git", tag = "v1" }
```

- `members` are directories below the root; a trailing `/*` means every child directory holding an `ms.toml`. Nothing else (no `exclude`, no nested workspaces).
- `path` is the fourth dependency form beside `tag`, `sha` and `version`: it must name a member, is never written to `ms.lock`, and is imported like any package (`@util/x.ms`). Confinement stays: a member's files and path targets lie inside the workspace root.
- A member's own dependency names are private to it, as for fetched packages. Cycles between members are an error naming the cycle.
- One `ms.lock` at the workspace root pins every git dependency of every member; the resolver takes all member manifests as roots (packages thread's design), so two members that share a dependency share one copy.
- Commands find the workspace by walking up from the member (or from `ms.toml` argument). `ms build|run|check|test|lint` inside a member act on it; at a root with no `[project]` they need `-p <name>` or `--workspace` (build each executable member, check/test/lint all). No default member.

**Effects.** Same rule as fetched packages: a member declares `effects` in `[project]`; an importing member must allow it under `[effects]`. One mechanism, no workspace exemption (open question 1).

**Compile unit and cache key (stage 3).** The package is the unit of codegen caching, not of separate checking. The front end still loads, checks and lowers the whole workspace (measured floor above); what is cached is the object file.

- Each package yields one object with its non-generic functions plus the instances it needs, emitted as local symbols (duplicated per package; no weak symbols or COMDAT, so ELF, Mach-O and COFF behave the same).
- Key = SHA-256 of: the package's lowered MIR text (after optimize and unwind), the interface fingerprint of each package it uses, the `ms` version, ISA flags and `BuildOptions`. The interface fingerprint covers public signatures, type layouts and the bodies of anything the optimizer may inline or monomorphize into a dependent. A body-only edit to a non-inlinable function changes the package's object but not its dependents'.
- Cross-package symbols are content-stable names (module path, name, signature hash), replacing `name#{index}` and queue-ordered glue names in `crates/ms-clif/src/cg.rs`. This is the prerequisite from `incremental-builds.md` and also makes objects deterministic.
- Objects live in `.ms-cache/obj/<hash>`, written by atomic rename; a corrupt entry is a miss; `MS_CACHE=off|verify` already exist and apply.
- The whole-build mtime cache stays as the first check.

**Summary files.** None in stages 1 and 2. Real projects re-check in 7 to 48 ms (parked in `incremental-builds.md`); a per-package checking summary is added only if a workspace's check time exceeds 100 ms after stage 3, and then follows that proposal.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/{manifest,packages}.rs` | `[workspace]`, `path` form, member discovery, cycle check; roots passed to the resolver | `crates/ms-driver/tests/project_workspace.rs` |
| `crates/ms-driver/src/load.rs`, `paths.rs` | confine to the workspace root; member packages in `Project::packages` | unit + conformance fixture with two members |
| `crates/ms-cli` | `-p`, `--workspace`, workspace discovery from a member | `crates/ms-cli/tests/workspace.rs` on a temp workspace, all platforms |
| `crates/ms-check/src/effects.rs` | none beyond treating members as packages | existing package effect cases plus one member case |
| `crates/ms-clif`, `ms-build` (stage 3) | stable names, per-package objects, cache | warm-cache objects link and run identically; fault trace fixture |
| `documentation/`, `wiki/` | workspaces page; cache layout | `make docs-check` |

## Alternatives

- Do nothing: no way to split a repository into packages, 4.7 s Debug rebuilds at 122k lines.
- Workspace without the cache (stages 1 and 2 only): useful for organization; not the speed goal.
- Separate compilation with interface files for checking: floor is already low (1.7 s at 122k lines), and monomorphized generics and inlining need dependent bodies anyway.
- Per-function cache: dropped by Chinmay on 2026-10-31 ("keep the cache simple").
- Cargo-style `[workspace.dependencies]` and `exclude`: later if needed.

## Stages

1. Workspace manifest, members, path dependencies, shared lock, commands; after the packages TOML PR and `ms add/install/remove` merge. Gate: temp-workspace test on Linux, macOS, Windows CI.
2. Docs, `ms init --workspace`, search_symbol, lint, diagram and LSP across members.
3. Spike, then build, the object cache on Cranelift. Gate (measured on the workload above, one-function edit in a leaf package): Debug rebuild at most 3.0 s (from 4.7 s), i.e. codegen under 0.3 s of the 2.1 s; and identical executable output. If not met, drop and record.
4. Not decided here: per-package LLVM partitions for Release (37.7 s); costs cross-package inlining and needs a `bench/perf` regression run.

## Expected win

- Debug rebuild after a leaf edit: about 4.7 s to 2.6 s (codegen 2.1 s becomes under 0.2 s; check 1.7 s and lowering 0.5 s remain). Estimate, not measured; the spike measures it.
- The floor is then the front end. For projects in the 10k-line range checking is about 10 to 50 ms, so the cache matters most for large workspaces.

## Open questions

1. Should members trust each other without an `[effects]` entry? Recommendation: no, keep one rule; revisit if it is noisy in a real monorepo.
2. Should a root manifest with `[workspace]` also allow `[project]` (a root package, as in Cargo)? Recommendation: yes, no extra rule.
