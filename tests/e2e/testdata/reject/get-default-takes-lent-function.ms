// `m.get(k)` lends the element; `get(default)` on that optional would take a function value
// out of the map, which has one owner and cannot be copied. Read it in place with
// `if let`.
fn pick(m: Map[Int, fn() String], s: String) String:
	return m.get(7).get(fn: s + "y")()

export fn main() Int:
	return pick({7: fn: "a"}, "b").length()
