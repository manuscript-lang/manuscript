# Type aliases and closed type sets

## Summary

- Problem: `List[T].sum` is nine near-identical methods, one per number type, because no bound names "Int or Float". A magic `Numeric` bound was rejected.
- Change: `type Numeric = Int | Float | ...` declares a closed set of existing types, erased at compile time. `T: Numeric` accepts exactly its members; operators work when every member allows them. `type N = T` is a plain alias.
- Decision (approved by Chinmay): this syntax. Runner-up: unbounded `fn List[T].sum() T` checked per call (Alternatives).

## Status

- Proposal, 2026-11-11, against `822e8f9a`. Implemented 2026-11-11: aliases, sets, and the `sum` collapse.
- Direction (Chinmay): "reduce our dependence on magic bounds"; "not runtime, compile time tagged union"; both `type Numeric = Int | Float ...` with `T: Numeric`, and bound-free `fn List[T].sum() T`, were offered. This file takes the first: the signature stays honest.

## Problem

- `stdlib/collections/collections.ms` holds `sum` for `Int`, `Float`, `Int8`, `Int16`, `Int32`, `UInt8`, `UInt16`, `UInt32` and `Float32`, plus nine one-method `ListXSum` interfaces. Bodies differ only in the type name.
- Today `T` is checked once as an opaque variable: `+` and the literal `0` on it are rejected, so the generic form cannot be written.

## Design

```manuscript
type Numeric = Int | Int8 | Int16 | Int32 | UInt8 | UInt16 | UInt32 | Float | Float32

// An empty list sums to 0. Example: `[1, 2, 3].sum()` is `6`.
fn List[T: Numeric].sum() T:
	var total: T = 0
	for x in self:
		total += x
	return total
```

- `type N = A | B` (`=` after the name) is a set; `type N = T` is an alias; `type N:` stays a record. Members are types, so there is no tag, no layout and no `match` on a set.
- A set may only bound a type parameter; as a value type it is rejected: `a type set constrains a type parameter; it has no values`.
- Generic code is monomorphized. A set-bounded body is checked once with `T` as a parameter: an operator is allowed when every member allows it, and `0` is the zero of every numeric member. Each instance then lowers with its own arithmetic.
- An alias target is any type expression, not just these two cases: `type Handler = fn(Request) Response`, `type MaybeRow = Row?`, `type Parsed = Row!Error`, `type Rows = List[Row]`. A set `A | B` is one more type expression, allowed only where a bound is.
- Generic aliases (`type Pairs[T] = List[Pair[T, T]]`) follow the generic-parameter rules; recommend including them in stage 1.
- Aliases are transparent: an alias is another name for the same type, not a new type, so the two are interchangeable everywhere.

```manuscript
type Rows = List[Row]

fn count(rows: Rows) Int:
	return rows.length()

xs: List[Row] := load()
n := count(xs)          // accepted: Rows is List[Row]
ys: Rows := xs.clone()         // accepted, and Rows has every List[Row] method
```

  A distinct type needs a record (`type Rows: items: List[Row]`), which is not interchangeable with `List[Row]`.
- Sets may name sets (flattened); interfaces are not members; recursion is rejected.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` | defer marked bodies to instantiation; call-site diagnostic; cache per `(method, T)` | conformance accept (all number types) and reject (`String`, record) cases |
| `ms-lsp`, `ms-tooling` | availability of such methods on a receiver | tooling tests |
| `stdlib/collections/collections.ms` | one `sum`; delete nine methods and interfaces | `list-aggregates` fixture |
| docs, wiki | generics page: new rule; stdlib-design lesson on element-bound ops | doc build |

## Alternatives

- Do nothing: nine copies stay; each numeric helper multiplies the problem.
- Built-in `Numeric` bound: small diff, but a hard-coded compiler list and special rules for `+` and `0` on variables. Rejected as magic.
- Bound-free `fn List[T].sum() T`, body checked per call: no new syntax, but the signature hides what `T` may be, the method shows on every list, and errors surface at calls. Runner-up.
- Runtime-tagged union: rejected by direction; adds a tag and a branch to a hot loop.

## Stages

1. Aliases only, with docs. Check: alias conformance cases.
2. Sets; collapse `sum` and similar duplicates. Check: `make conform`, `list-aggregates`, `sum` perf against the latest `bench/perf/` baseline.

## Open questions

- Resolved (Chinmay, 2026-11-11): a plain `0` literal is accepted for a numeric set's parameter, as the zero of every member; no other literal converts.
- Per-member checking was not needed: the body is checked once with `T` as a parameter whose set members are all numeric, and lowering gives each instance its own arithmetic. A set whose members are not all numeric allows no operators.
