// conform: tags=testing,tier-core
// conform: phase=check
fn find(hold m Map[String, List[Int]], hold key String) &List[Int]? {
	return m.get(key)
}

test "a function returning Map.get borrows the map" {
	var m Map[String, List[Int]] = {"a": [1]}
	found := find(m, "a")
	m.add("b", [2])
	print(found != null)
}
// expect-error: MS3000 10:5 cannot change `m` while `found` borrows it (binding of a part of it, at 9:5); finish using `found` before this, or give `found` its own value by ending its initializer with `.clone()`
