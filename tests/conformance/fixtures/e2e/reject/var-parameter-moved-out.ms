// conform: tags=testing,tier-core
// conform: phase=check
fn rewrap(var xs: List[Int]) Unit:
	// Binding the caller's value elsewhere moves it out of the parameter.
	old := xs
	xs = [old.length()]

export fn main() Int:
	var xs = [1, 2, 3]
	rewrap(var xs)
	return xs[0] - 1
