# A returned `Map.get` is a borrow, not a copy

A function that returns `m.get(k)` returns a borrow of the map entry (`opt.view` over `msrt_map_get_ptr`), like `xs.get(i)`. Before 2026-11-07 the checker made such a function own its result, so every call deep-copied the value (`json.navigate` 105 ns against 57 ns). Chinmay approved the language change: "get can return a borrow".

- A caller that holds the result cannot change the map until its last use; `.clone()` the result first (see `stdlib/data/toml.ms`, `lookup`).
- `xs.first()` / `xs.last()` still return an owned `Optional`.
- If a stdlib function documents "the result borrows from the receiver", check that the emitted MIR (`ms emit`) ends in `opt.view`, not `opt.some` of a `take`.
