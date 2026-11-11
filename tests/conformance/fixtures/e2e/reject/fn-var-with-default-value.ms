// conform: tags=testing,tier-core
// conform: phase=check
fn push(var values: List[Int], value: Int = 1) Unit:
	values.append(value)

export fn main() Int:
	var values: List[Int] = []

	// A function value fills defaults in a thunk that cannot also pass a var parameter.
	change := push
	change(var values, 2)
	return values.length() - 1
