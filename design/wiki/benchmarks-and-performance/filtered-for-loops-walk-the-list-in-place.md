[Wiki](../index.md) › [Benchmarks and performance](index.md)

# `for x in xs.filter(f)` walks `xs` in place

Verified (2026-11-18): the loop built the filtered list first, deep-copying every kept element (a record with a `List[Item]` in c13-inventory-orders), then took them back out one by one. The `for` lowering (`src/compiler/lower/lower_for.c`) now walk `xs` by index, borrow each element and skip it when a lambda says no. c13: 392M to 350M instructions on 400 KB of input.

The rule is narrow on purpose: the source is a name or field path the body leaves alone, the loop variable is only read, and every lambda is one `return` of names, literals, fields, comparisons and `and`/`or`/`not`. Those cannot fault, so running them as the loop reaches each element, instead of up front, shows nothing different. Arithmetic and indexing can fault and keep the built list. Any `filter` followed by `map` also keeps it.

Apply when: a `for` over `filter` still allocates, or you widen the lambda rule (then decide which fault comes first).
Evidence: fixture `e2e/accept/filter-walk-loops`; `bench/perf/workloads/results.md` (2026-11-18).
Verify: `make conform`; `MS_EMIT_OPT=1 ms emit` shows no `clone`/`list.push` in the loop.
