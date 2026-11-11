# Collections and pipelines

Prelude constructors: `[1, 2]`, `List[Int](reserve: 8)`, `Map[String, Int]()`, `Set[Int]()`. Mutation requires var.

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

Map `.get(key)` returns Optional; `.get_or(key, default)` supplies a fallback. Iterate `.entries()` and read `.key`/`.value`. List `.slice(start, end)` returns Result; `.get(index, default)` supplies a fallback.

`x | f(a: 1)` passes x first; `x | .m()` calls a method; `x | f?` propagates f's Result. Thus `x | f(a: 1) | g? | .m()` means `(g(f(x, a: 1))?).m()`.

List `.filter/.map/.sum` are methods; similarly named stream steps are imported functions. Prefer these operations to bookkeeping loops.
