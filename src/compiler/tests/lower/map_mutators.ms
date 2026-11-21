fn main() Int:
	var m = Map[Int, Int]()
	m.add(1, 2)
	m.remove(1)

	var n = Map[String, String]()
	n.add("a", "b")
	n.remove("a")
	n.clear()

	var s = Set[Int]()
	s.add(3)
	s.remove(3)
	s.clear()

	var names = Set[String]()
	names.add("x")
	if s.contains(3): return 1
	if names.is_empty(): return 2

	return s.length() + names.length()
