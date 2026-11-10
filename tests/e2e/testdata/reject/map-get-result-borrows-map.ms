fn find(m: Map[String, List[Int]], key: String) List[Int]?:
	return m.get(key)

test "a function returning Map.get borrows the map":
	var m: Map[String, List[Int]] = {"a": [1]}
	found := find(m, "a")
	m.add("b", [2])
	print(found.is_some())
