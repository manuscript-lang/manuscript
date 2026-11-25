// conform: tags=maps,stdlib-collections,tier-core
// conform: phase=run
type Item {
	name String
	tags List[String]
}

fn label(n Int) String {
	return f"built-{n}"
}

fn main() Void {
	var names = Map[String, String]()
	names.add("a", "stored-a")

	// A heap default that is used, a heap default that is not, and a literal default.
	print(names.get_or("missing", label(1)))
	print(names.get_or("a", label(2)))
	print(names.get_or("missing", "literal"))

	// Keeping the result makes the one copy.
	kept := names.get_or("missing", label(3)).clone()
	names.add("b", kept)
	print(names.get_or("b", "none"))

	// A list default that is used and changed through a copy.
	var groups = Map[String, List[String]]()
	var list = groups.get_or("x", [label(4)]).clone()
	list.append("more")
	groups.add("x", list)
	print(groups.get_or("x", []).length())

	// A record default holding heap fields.
	var items = Map[String, Item]()
	items.add("one", Item("first", ["t1", "t2"]))
	print(items.get_or("none", Item(label(5), [label(6)])).name)
	print(items.get_or("one", Item(label(7), [])).tags.length())
}
