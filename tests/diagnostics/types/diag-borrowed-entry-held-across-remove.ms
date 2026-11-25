// conform: tags=diagnostics,mutation,maps,tier-core
// conform: phase=check
// conform: origin=issue 2181
fn held() Int {
	var m = Map[String, List[Int]]()
	m.add("a", [1, 2, 3])

	x := m.get("a")
	m.remove("a")
	return (x or []).length()
}
// expect-error: MS3000 9:5 cannot change `m` while `x` borrows it (binding of a part of it, at 8:5); finish using `x` before this, or give `x` its own value by ending its initializer with `.clone()`
