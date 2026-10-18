# c13 / c35 Manuscript references

- `unit` is a reserved value keyword and cannot be a binding name (hit with `let unit = price`); use another name.
- `String.parse_int()` returns `Optional[Int]`, not `Result` (no `.ok()`); validate digits manually before parsing.
- `String.trim()` strips all Unicode whitespace, not just spaces/tabs, so c35 uses a hand-written `trim_st` over `scalar_values()`/`slice`.
- No `Map` entry-update or default-get: increments are `m.add(key:, value: m.get(k).get(0) + n)`.
- Parameter-free early `return emit(...)` of a Unit call works as an early exit idiom in Unit functions.
