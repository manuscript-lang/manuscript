# The C body checker admits maps by key and value type

- `check_map.c` admits `Map[K, V]` with `K` in `Int`, `String`, `Bool` (the key bounds hold without a lookup) and `V` any admitted type; annotations and literals only. An empty literal with no expected type, a `Float` key and every method stay with Rust.
- The ownership walk still declines a function holding a map (`ownership-declined` in the facts dump); map ownership and `lower_map.c` are the next slices. Lists own their own files (`check_list.c`, `lower_list.c`): follow their shape for index, `for` and drops.
