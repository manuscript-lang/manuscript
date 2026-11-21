type Item:
	id: Int

fn lookup(m: Map[String, Item]) Int:
	return m["a"].id

fn names(m: Map[Int, String]) Int:
	return m[1].length()

fn main() Int:
	items: Map[String, Item] := {"a": Item(id: 3)}
	words: Map[Int, String] := {1: "xy"}
	return lookup(items) + names(words)
