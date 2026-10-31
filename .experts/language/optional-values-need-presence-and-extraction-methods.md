[Wiki](../index.md) › [Language](index.md)

# Optional values need presence and extraction methods

Decision: the user explicitly rejected relying on `match` for routine Optional handling. Keep one receiver surface: `is_some`, `is_none`, and `get(default)`; `get_or_else` takes a lazy payload fallback and `or_else` a lazy Optional fallback. `unwrap`, `unwrap_or`, `unwrap_or_else`, `unwrap_error`, and `at` are removed (Result keeps `get(default)`, `get_or_else`, `or_else`, `map_error`, `err`). Preserve Optional as an ordinary alternative; these methods do not introduce flattening or new syntax. The private native helpers are implementation bindings, not exported aliases.

---
Topics: [Optionals](../topics/optionals.md)
