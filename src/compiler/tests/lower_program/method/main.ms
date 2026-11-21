import Counter, make from "./shapes.ms"

fn main() Int:
	var c = make(2)
	c.bump(3)
	return c.total(4)
