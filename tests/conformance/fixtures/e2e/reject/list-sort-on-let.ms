// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
	items := [2, 1]
	items.sort()
	return items.length()
