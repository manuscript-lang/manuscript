// conform: tags=testing,tier-core
// conform: phase=check
test "the map cannot change while a var borrows its entry":
	var m: Map[String, List[Int]] = {"a": [1]}
	var entry = m.get("a").get()
	m.add("b", [2])
	entry.append(2)
