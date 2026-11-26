# `m.get(k) or d` answers a view of the entry or of `d`, not a copy

`Map.get_or` is `fn hold ...get_or(key, hold fallback U) &U { return self.get(key) or fallback }`, so its answer is a part of the map or of the fallback and nothing is copied. Three places agree on that:

- The result-borrow classifier joins both sides of `x or d` when the left is a call and `d` is a place (a name or member); a moved left (`value or fallback`) stays an owner, so the fallback is still copied there.
- Lowering reads `m.get(k)` in place (`fn_map_entry_view`, the entry view of any value type, which `fn_map_get_view` gates to resources) and `lower_or_view` answers the fallback place as an `opt.view`, not a moved copy. A native `get` read any other way is a copy of the entry: viewing that copy and dropping it at scope end frees what the answer points at, and a short test does not notice (read the pointer back after a few allocations, or run valgrind).
- A value that is itself an Optional is stored as it is and the answer wraps it once more, so there is no entry to view. `fn_map_entry_view` declines and `borrows_result` keeps such an instance an owner (`returns_entry_or`).

A `var` bound to a borrowing call holds the view only while every later store is a borrowing call too (`var_stores_owned`); `found = own.clone()` or `found += "!"` makes it an owner, so the binding copies. Before, the owned store in an inner scope was dropped at its end and the verifier reported a value used after it was consumed.
