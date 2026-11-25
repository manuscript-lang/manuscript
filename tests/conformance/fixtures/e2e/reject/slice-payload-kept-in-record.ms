// conform: tags=testing,tier-core
// conform: phase=check
// `get(default)` and `or_else` hand back the payload of a lent slice, so a position that keeps
// it (here a record field) needs `.clone()`, as it does for `slice(..)?`.
type Box {
	items List[Int]
}

export fn main() Int {
	var xs = [1, 2, 3, 4]
	boxed := Box(xs.slice(0, 2).get_or([]))
	return boxed.items.length()
}
