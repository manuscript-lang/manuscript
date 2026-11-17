# `get_or` for fallbacks, `get` for lookups and asserts

## Summary

- `get` has four meanings today. `o.get(d)` is a fallback, `o.get()` faults, `m.get(k)` is a lookup that returns an optional, and `xs.get(i, d)` is a fallback with the index first. Agents mix them: the chained `m.get(k).get(d)` appears about 250 times in repo `.ms` code, mostly in agent-written sources, although `m.get_or(k, d)` exists.
- Rename the fallback forms to `get_or`: `Optional.get_or(d)`, `Result.get_or(d)`, `List.get_or(i, d)`, `Bytes.get_or(i, d)`. Bare `get()` stays and only asserts (faults on `none`/error).
- No new keyword, operator or type. Chinmay approved this direction on 2026-11-16 (the `or` operator was rejected).

## Status

- Proposal, 2026-11-17, checked against the stacked branch of PRs #4382 and #4383.
- Not in scope: `xs.get(i)` returning `T?` like `map.get(k)`. About 1,750 bare `.get()` sites and most `xs.get(i)` sites rely on the lent plain element, so it is a separate change.

## Problem

- Measured on the pre-migration tree (tracked `.ms` files outside `bench/agent/results`): about 2,000 one-argument fallback `.get(d)` sites on Optional and Result, about 160 two-argument `xs.get(i, d)` sites, about 1,750 bare `.get()`, about 250 chained `get(k).get(d)`. Earlier all-`get(` counts of 4,700 included `Map.get(k)` and are not used here.
- One name for "safe fallback" and "fault on absence" means a reader cannot tell from the call whether it can fault without counting arguments.
- `Map` already uses `get_or(key, default)`; `List` and `Optional` do not, so the same job has two spellings.

```manuscript
fn display_name(name: String?, names: List[String]) String:
    return name.get("Anonymous") + names.get(0, "")
```

After:

```manuscript
fn display_name(name: String?, names: List[String]) String:
    return name.get_or("Anonymous") + names.get_or(0, "")
```

## Design

- `Optional[T].get() T` and `.get_or(default: T?) T`; the same pair on `Result[T, E]`, `List[T]` (`get_or(index, default)`), and `Bytes`.
- The old `get(default)` and `get(index, default)` are removed, not deprecated: a call now fails with `too many positional arguments; ... did you mean 'get_or'?` and `ms check --fix` renames it (`tests/removed/get-default.ms`).
- Lowering is unchanged: for Optional, Result, List and Bytes the checker gives `get_or` the native identity `get` (one mapping in `contracts.rs`), so the existing lowering and borrow rules apply as before. `Map.get_or`, `SortedMap.get_or` and `RouteParams.get_or` are separate declarations with a plain fallback type and are untouched. The `default: T?` parameter type on the new forms is the old `get` parameter, kept so an omitted default still means "none" for an optional payload.
- `ms check --fix` renames the method name only, at the arity error on a call named `.get`; it never edits `Map.get(k)` because that call has no extra argument.
- Lint: `MSL120` now matches `map.get(k).get_or(d)` and rewrites it to `map.get_or(k, d)`; MSL110 text says `get_or`.

## Components touched

| Component | Change |
| --- | --- |
| `stdlib/core/core.ms`, `collections.ms`, `bytes.ms` | split declarations |
| `crates/ms-check` | native identity for `get_or`; `get_or` passthrough in ownership; arity hint with fix |
| `crates/ms-lower` | bound native calls map `get_or` to `get` |
| `crates/ms-tooling` | MSL110 and MSL120 text and match; docs, agent skill, standard-call table |
| repo `.ms`, docs | mechanical migration driven by the checker's arity errors |

## Alternatives considered

- Keep one `get` and add `or`: rejected by Chinmay.
- `unwrap_or`/`unwrap` names: removed earlier on purpose (wiki: optional values need presence and extraction methods).
- Make `xs.get(i)` return `T?` now: larger blast radius, separate change.
- Do nothing: agents keep chaining `get(k).get(d)` and the fault/fallback distinction stays hidden.

## Verification

- `make conform`, `make bench-check`, `make docs-check`, `make removed-check`, `cargo test -p ms-tooling -p ms-check`.
- A before/after count of `.get(d)` sites shows zero remaining.
