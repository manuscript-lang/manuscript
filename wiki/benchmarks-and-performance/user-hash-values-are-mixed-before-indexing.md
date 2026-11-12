# User `hash()` values are mixed before they index a table

A record key with `fn T.hash() Int: self.x * 31 + self.y` hands the map near-consecutive hashes, which cluster under linear probing (`Set[Pt]`, 1M operations: 562 ms against 103 ms mixed). `DynKey::hash` in `ms-rt/src/map.rs` applies `hash_int` to every custom hash; built-in key kinds were already mixed. Do not trust a user hash for distribution, and keep a `Set` of small-int-pair records in `bench/perf/element-types`. Evidence: `bench/perf/element-types/README.md`.
