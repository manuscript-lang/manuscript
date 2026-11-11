// conform: tags=testing,tier-core
// conform: phase=check
extern fn total(values: List[List[Int]]) Int

export fn main() Int:
	return total([[1, 2]])
