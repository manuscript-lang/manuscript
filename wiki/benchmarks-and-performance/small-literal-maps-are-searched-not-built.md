# Small literal maps are searched, not built

Agent programs write lookup tables inline: `{"open": 3, "report": 1}.get(cmd).get(0)`. Lowering built the map (allocation plus one `msrt_map_add` per entry) on every evaluation: 85 ns per five-entry lookup against about 2 ns for a `match`, 10 to 25% of `c13` and `c36`.

- `ms-lower/src/constmap.rs` answers `get`, `get(..).get(default)`, `is_some`, `is_none` and `contains` on a literal of at most 12 constant entries by comparing the key with each constant, last duplicate first. `const_map_table` decides what counts as constant (the same rule the large-literal table builder uses).
- A literal that is bound, passed on, iterated or longer than 12 entries still builds the map. Caching a built map in a static was rejected: it needs a once-initialized cell shared across isolates and an exit hook so the leak sweep stays clean, for no gain on these sizes.
- Evidence: `bench/perf/codegen-2026-11-12.md`; fixture `e2e/accept/constant-literal-map-lookups`.
