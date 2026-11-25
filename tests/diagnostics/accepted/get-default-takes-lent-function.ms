// conform: tags=testing,tier-core
// conform: phase=check
// `m.get(k)` lends the element, and `or` falls back to a closure that keeps `s`: the closure
// outlives the call, so `s` is taken with `move` (a borrowed `s` would need `.clone()`).
fn pick(m Map[Int, fn() String], move s String) String {
	return (m.get(7) or (() => s + "y"))()
}

export fn main() Int {
	return pick({7: () => "a"}, "b").length()
}
// expect-exit: 0
