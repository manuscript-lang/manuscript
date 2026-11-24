# Workspaces and per-package compile

## Summary

- Problem: a project is one `ms.toml` at one root; code cannot be split into packages inside one repository, and every `ms build` redoes all codegen after any edit.
- Change: a root `ms.toml` with `[workspace] members`, path dependencies between members, one `ms.lock`; then a per-package object cache so an unchanged package is not recompiled.
- Decision requested: approve the manifest shape (user-visible) and the staging; the object cache (stage 4) goes ahead only if its spike meets the gate below.

## Status

Proposal, approved for stages 1 to 3 by the review lead and Chinmay, 2026-11-15; stage 1 built on `#4090`. Direction (Chinmay): "workspaces, and a way of organizing code and speeding up compile with packages". Builds on `design/proposals/packages.md` (git dependencies, effects) and the parked checking cache in `design/proposals/incremental-builds.md`. The packages thread owns the dependency table, `ms add/install/remove` and the resolver (`/mnt/project-files/packages/package-resolution.md`); this proposal adds to them and waits for manuscript#4090.

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
- One `ms.lock` at the workspace root pins every git dependency of every member. The resolver takes all member manifests as roots and keys by resolved copy, so members that share a dependency share one copy.
- Commands find the workspace by walking up from the member (or from `ms.toml` argument). `ms build|run|check|test|lint` inside a member act on it; at a root with no `[project]` they need `-p <name>` or `--workspace` (build each executable member, check/test/lint all). No default member.

**Effects.** Same rule as fetched packages: a member declares `effects` in `[project]`; an importing member must allow it under `[effects]`. One mechanism, no workspace exemption (open question 1).

**Compile unit and cache key (stage 4, gated).** The package is the candidate unit of an object cache, not of separate checking; the front end still checks and lowers the whole workspace.

- Key = SHA-256 of exactly what the object is a function of: the package's final MIR (after inlining and monomorphization), the layouts and symbol names it references, the `ms` version and `BuildOptions`. No interface fingerprint: it would be a second description of what leaks across packages. If final MIR lacks an input, the spike lists it.
- Duplicated instances, descriptors and tables per package are safe only if nothing compares their addresses (type identity, interface dispatch, closures, statics in generics); the spike states what was checked.
- Spike also reports module-level granularity (hit rate, object count, link time), then picks package or module as the unit, and measures the cost of printing and hashing the MIR.
- Objects in `.ms-cache/obj/<hash>`, atomic rename; a corrupt entry is a miss; `MS_CACHE=off|verify` apply.

**Summary files.** None in stages 1 to 3. Real projects re-check in 7 to 48 ms (parked in `incremental-builds.md`); a per-package checking summary is added only if a workspace's check time exceeds 100 ms after stage 4, and then follows that proposal.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/{manifest,packages}.rs` | `[workspace]`, `path` form, member discovery, cycle check; roots passed to the resolver | `crates/ms-driver/tests/project_workspace.rs` |
| `crates/ms-driver/src/load.rs`, `paths.rs` | confine to the workspace root; member packages in `Project::packages` | unit + conformance fixture with two members |
| `crates/ms-cli` | `-p`, `--workspace`, workspace discovery from a member | `crates/ms-cli/tests/workspace.rs` on a temp workspace, all platforms |
| `crates/ms-check/src/effects.rs` | none beyond treating members as packages | existing package effect cases plus one member case |
| `crates/ms-clif`, `ms-build` (stages 3, 4) | stable names; per-package objects, cache | warm-cache objects link and run identically; fault trace fixture |
| `documentation/`, `design/wiki/` | workspaces page; cache layout | `make docs-check` |

## Alternatives

- Do nothing: no way to split a repository into packages. The speed case alone is weak (a stale object is a miscompile), which is why the cache is gated.
- Parallel codegen as the speed fix: already done.
- - Separate compilation with interface files for checking: floor is already low (1.7 s at 122k lines), and monomorphized generics and inlining need dependent bodies anyway.
- Per-function cache: dropped by Chinmay on 2026-10-31 ("keep the cache simple").
- Cargo-style `[workspace.dependencies]` and `exclude`: later if needed.

## Stages

1. Workspace manifest, members, path dependencies, shared lock, commands; after the packages TOML PR and `ms add/install/remove` merge, with the resolver interface (a set of root manifests) agreed in writing with the packages thread. Gate: temp-workspace test on Linux, macOS, Windows CI.
2. Docs, `ms init --workspace`, search_symbol, lint, diagram and LSP across members.
3. Content-stable symbol names and deterministic objects (own PR, reproducible builds): two builds of one source give identical objects.
4. Object cache spike, built only if it passes: leaf-edit Debug rebuild at most 2.6 s on the workload, cold build and link at most 2% slower, byte-identical executable with the cache on, off and verify, and `MS_CACHE=verify` over the corpus in the nightly safety run, not on pull requests.
5. Release (37.7 s) is the larger pain; not started here.

## Expected win

- Cranelift codegen is already parallel (`cg.rs`). Measured, Debug, same workload: codegen 5.9 s on 1 core, 2.7 s on 4 cores. More threads will not remove the rest, so a cache is the only further lever for codegen.
- Leaf edit with a cache: about 4.7 s to 2.6 s (estimate; check 1.7 s and lowering 0.5 s remain). Real projects check in 7 to 48 ms, so the cache matters only for very large workspaces; this is why stage 4 is gated and optional.

## Stage 4 result (2026-11-16): not built

Spike on 72k lines in 1,001 modules and 12k functions (release `ms`, 4 cores, Debug, `MS_CACHE=off`): build 1.8 s, of which codegen 1.6 s. Pinned to one core, codegen takes 1.9 s. Cranelift compilation already runs on the other cores, so it adds under 0.5 s of that wall time; the rest is single-threaded lowering, which a cache keyed on final MIR still has to run to rebuild symbols, glue and tables. The most a perfect object cache saves is about 20% of a Debug build, against the gate's 45% (4.7 s to 2.6 s). Stage 4 is dropped; reopen it only if lowering becomes parallel and a workload shows compilation dominating.

## Open questions

Decided in review: members need the same `[effects]` entry as packages (one rule), and a root with `[workspace]` may also hold `[project]`. Chinmay sees both before merge.
