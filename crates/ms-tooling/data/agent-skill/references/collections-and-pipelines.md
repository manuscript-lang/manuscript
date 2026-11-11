# Collections and pipelines

List, Map and Set are in the prelude. Construct `[1, 2]`, `List[Int](reserve: 8)`, `Map[String, Int]()` and `Set[Int]()`. Mutating contents requires a `var` binding or parameter.

Save as `collections.ms`:

<!-- complete: collections.ms -->
```manuscript
fn main() Int:
    values := [1, 2, 3, 4]
    total := values | .filter(fn x: x > 2) | .map(fn x: x * 2) | .sum()
    var counts = Map[String, Int]()
    counts["total"] = total
    if var n = counts["total"]?:
        n += 1
    if counts.get_or("total", 0) == 15: return 0
    return 1
```

`ms run collections.ms` prints nothing and exits 0.

- `map.get(key)` returns Optional; `map.get_or(key, default)` supplies a default. Iterate `for entry in map.entries():` and read `.key` / `.value`.
- `list.slice(start, end)` returns Result. Use `.get(index, default)` for a fallback; do not assume index operations cannot fail.

`x | f(a: 1)` passes x as f's first argument. `x | .method()` calls a receiver method. `x | f?` propagates f's Result. Thus `x | f(a: 1) | g? | .m()` means `(g(f(x, a: 1))?).m()`.

List operations such as `.filter`, `.map`, `.sum` are methods. Stream transformations with similar names are imported free functions; do not interchange their call shapes. Prefer the short methods over bookkeeping loops when they express the task directly.
