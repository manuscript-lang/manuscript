# Package resolution: semver requirements, one copy per compatible range

## Summary

- Problem: each dependency names one exact tag, and two packages that need different tags of a third give a type error where Cargo would pick one version for both.
- Change: follow Cargo. A dependency names a semver requirement (caret by default); the resolver picks one version per compatible range across the whole graph; different majors coexist as separate copies with distinct types; `ms.lock` pins one entry per resolved copy; a package's `[project] version` must match its tag.
- Decision requested: approve the manifest field, the resolution procedure, the module identity of a copy, and the lock format.

## Status

Draft 2, 2026-11-15, after review. Direction from Chinmay: follow Rust for now. This replaces the rule in `design/proposals/packages.md` that two tags of one package are an error when their types meet (it stays true for two majors).

## Problem

If `@a` needs `v1.2.0` of `@c` and `@b` needs `v1.4.0`, the build keeps two copies and a value crossing between them fails with "two versions of the package are in the tree".

## Design

**Manifest.** A dependency gets `version`, a semver requirement on tags `vMAJOR.MINOR.PATCH` (leading `v` optional): `"@pg" = { url = "...", version = "1.2" }`, meaning `^1.2`. Exactly one of `version`, `tag` (an exact tag name, unchanged) and `sha` (exact commit, unchanged). Operators: `^` (default), `~` and `=`, as Cargo; `^0.4.1` means `>=0.4.1, <0.5.0`. `>=`, `<` and comma ranges are left out: they can span majors, which breaks one copy per compatible range and would force backtracking. Pre-releases are skipped unless the requirement names one. Semver is parsed in the driver (no crate); `v1.2.3` and `1.2.3` both name version 1.2.3, and a repository that has both for one version is an error.

**Package version.** `[project]` takes an optional `version = "1.2.3"`: a string of three numbers, with an optional `-pre` suffix, no leading `v`. CalVer such as `2026.11.0` is valid, read as semver (the year is the major, so a caret requirement on it never crosses a year). An application leaves it out. A package that is used as a dependency declares it, and the resolver uses it as follows:
- A tag that parses as a version (`v1.4.2`, `1.4.2`) names that version. If the manifest at that tagged commit has a `version`, the two must be the same version, or the resolver errors: `ms-pg tag v1.4.2 holds ms.toml version 1.4.1; ask the author to fix the tag, or require =1.4.0 or earlier`. A mistagged release blocks every user of that bucket, so the message names the way out and the resolver never silently skips the tag. A tagged commit with no `version` takes the tag as its version.
- The tag is the source of truth for selection; the manifest `version` is only a consistency check and is never used to select.
- A `sha` pin's copy id (lock key and module prefix) is the sha. The manifest `version` is shown beside it in messages (`wire 1.4.2 at 709e53a`) and is never the id, so a sha-pinned copy cannot collide with the tagged copy of the same version at another commit.
- A tag that does not parse as a version is not selectable by `version` requirements, and, pinned with `tag`, is not checked.
- The check runs when a copy is fetched and again on every build from the lock, so an edited cache or manifest fails.

**Repository identity.** Two URLs name one repository when they match after: lowercase the host, drop a trailing `/`, drop a trailing `.git`. The scheme is not part of the key, so `http://` and `https://` forms are one repository (the fetch rules still decide which schemes are allowed). Nothing else is normalized (`www.`, ssh forms are different repositories). The key is `github.com/acme/wire`; a `file://` URL keeps its path as `file/path`.

**Buckets.** A bucket is `(repository, major)`, or `(repository, 0, minor)` for `0.x`, or `(repository, 0, 0, patch)` for `0.0.x`. A requirement belongs to the bucket of its base version (`^1.2` and `~1.2.3` are in bucket 1; `^0.4.1` in 0.4), so a requirement never spans buckets. One copy is built per bucket. `tag` and `sha` pins are exact (below).

**Resolution procedure** (`ms install`, `ms add`; the lock is used as-is when it satisfies the manifests):
1. Requirements = the project's own plus those of every currently picked copy's `[dependencies]`, each tagged with its asker. Tags come from `git ls-remote --tags` once per repository per run.
2. For each bucket, pick the highest tag satisfying every requirement in it. If none does, error naming the two (or more) askers with their requirements.
3. Exact pins: a `tag` or `sha` names one commit. Two pins of one repository unify only when they resolve to the same commit, otherwise the resolver errors naming both askers. A repository named by a pin and by a `version` anywhere in one graph is an error naming both askers; the resolver never picks between them.
4. If any pick changed, recompute from step 1: a copy's own requirements count only while the copy is picked, so a lowered pick withdraws what the old pick asked for. Repeat until no pick changes.
5. Termination: the loop is bounded at 64 rounds and fails with `dependencies do not settle: <repository> alternates between X and Y` rather than looping.
6. Unification is by repository key across names: `@pg` in the app and `@postgres` in a package are one copy when they share a bucket.

**Diamond.** `@a` wants `c ^1.2`, `@b` wants `c ^1.4`: one bucket `1`, one copy at the highest `1.x` satisfying both. `@b` wants `c ^2`: buckets `1` and `2`, two copies; a `C` from one passed to the other is the two-copies type error.

**Effects under unification.** The resolver may pick a newer version that declares more effects than some dependent allowed. That is an error naming the effect and the dependent (`@b allows std.net.* for wire; wire 1.4.2 also declares std.fs.write`), never a silent widening; the dependent edits its `[effects]` or its requirement. The check runs on every `check` and `build` from the lock and the manifests, not only at resolve, because a manifest can change after the lock was written.

**Lock.** One entry per resolved copy, keyed by copy id `github.com/acme/wire@v1.4.2` (repository key, `@`, chosen tag; a `sha` pin uses the sha): `"<id>" = "<url> <tag> <40 hex commit> sha256:<64 hex>"`. The mapping from a requirement to its copy is not stored. It is recomputed from the manifests: each requirement maps to the one locked copy of that repository whose bucket contains the requirement's tags, which is unique because buckets do not overlap. A manifest edit keeps every locked copy that still satisfies the requirements and re-resolves only the affected bucket. `ms install` with a satisfied lock lists no tags and needs no network beyond fetching missing copies; `ms install --update [@name]` re-picks. The lock is untrusted input as now.

**Roots.** The resolver takes a list of root manifests, not one manifest.

**Module identity.** A copy's canonical logical name prefix is `@<id>/`, for example `@github.com/acme/wire@v1.4.2/x.ms`. It does not depend on the path by which the copy was reached, so `@a/@c/x.ms` and `@b/@c/x.ms` are one module and types match; two majors have different prefixes and differ. Files and the story:
- `crates/ms-driver/src/project/packages.rs`: `Package.key` becomes the copy id; `attach`/`resolve` build one `Package` per copy and give each package's `Project` a `deps` map from its private names to the copy's source directory; lock reader and writer use copy ids.
- `crates/ms-driver/src/project/manifest.rs`: `package_of`, `scope` and `logical` find a copy by its cache directory (unchanged mechanism) and print `@<id>/path`; a copy is found once however many names reach it.
- `crates/ms-driver/src/load.rs`, `paths.rs`: `PackageScope.prefix` and `package_roots` use the copy prefix; a private name resolves through the importing package's `deps`, as now.
- `crates/ms-check` (`PackageScope`, effect cap, native ban, two-copies message): keyed by prefix; a unified copy's effect cap is its own declaration and every dependent's allowance must cover it (checked at resolve).
- `crates/ms-lsp` (`package_roots`, `package_documents` for search_symbol): one entry per copy, so a file is listed once; diagnostics and symbol pages show `@github.com/acme/wire@v1.4.2/x.ms`.
- `crates/ms-tooling` diagram: a node per copy, labelled with the id.

**Diagnostics.** The identity is `@github.com/acme/wire@v1.4.2/x.ms`. A message about an import also gives the name the importing file uses and the version (`@c, wire 1.4.2`), so the line in the manifest can be found.

**Errors.** `no tag of <repo> satisfies ^3.0 (asked by @b; tags: 1.0.0, 1.4.2, 2.0.1)`; `<repo> is needed at sha X by @a and at ^1.2 by @b`; `a version needs three numbers or an operator: write 1.2.0 or ^1.2`; two requirements in one bucket with no common tag: `@a asks <repo> ^1.2 and @b asks =1.1.0; no tag satisfies both`.

## Components touched

The files above, plus `crates/ms-cli/src/fetch.rs` (the install command, `ls-remote`), documentation and `design/proposals/packages.md`.

## Tests

Unit: the `version` field (accepts `1.2.3`, `2026.11.0`, `1.0.0-rc.1`; rejects `v1.2.3`, `1.2`, a non-string); requirement matching over a table (`^`, `~`, `=`, 0.x, prereleases, `v` prefix, both spellings of one version); a CalVer caret staying within its year; tag and `version` agreeing, disagreeing and absent; a `sha` pin with and without `version`. Resolver and integration on `file://` repositories with several tags: diamond unify (shared types); major split (two-copies message); 0.x split; a requirement withdrawn after a pick changes; a tag and a manifest `version` that disagree (with and without `v`), and a tagged commit with no `version`; a pin against a `version` (error naming both); two pins of different commits; a moved tag against the lock; an offline build from the lock; an effects-widening error; one repository under two names unifying; a satisfied lock listing no tags; an edited requirement re-resolving only its bucket; the round bound.

## Alternatives

- Exact tags only: no resolver, and every shared dependency fails or duplicates.
- Minimal version selection (Go): reproducible without a lock, but authors must keep minimums; Chinmay asked for Cargo.
- A backtracking solver: Cargo's bucket rule gives the same results for realistic graphs; the bound turns a pathological graph into an error.
- Lock keyed by path: stores references and duplicate lines.

## Open questions

- None; `version = "1.2"` means `^1.2`.
