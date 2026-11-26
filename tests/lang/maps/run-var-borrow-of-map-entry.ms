// conform: tags=maps,tier-core
// conform: phase=run
// `var x = map[key]` borrows the entry: changes through x reach the map, whatever happens to the key.
type Cell {
	hits Int
	names List[String]
}

fn bump(var c Cell, who String) Void {
	c.hits += 1
	c.names.append(who.clone())
}

export fn main() Int {
	var by = Map[String, Cell]()
	by["a"] = Cell(hits: 0, names: List[String]())

	var key = "a"
	var c = by[key]
	key = "zzz"
	c.hits += 10
	bump(c, "x")
	print(f"{by["a"].hits} {by["a"].names} {key}")

	var nested = Map[Int, Map[String, List[Int]]]()
	nested[1] = {"k": [1]}

	var inner = nested[1]["k"]
	inner.append(2)
	print(f"{nested}")
	return 0
}
// expect-exit: 0
// expect-stdout: 11 [x] zzz
// expect-stdout: Map(1: Map(k: [1, 2]))
