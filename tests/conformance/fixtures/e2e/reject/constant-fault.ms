// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
	items := [1, 2, 3]
	return items[1] / 0
