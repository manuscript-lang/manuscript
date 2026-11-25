// conform: tags=testing,tier-core
// conform: phase=check
fn rewrap(var xs List[Int]) Void {
	// Binding the caller's value elsewhere moves it out of the parameter.
	old := xs
	xs = [old.length()]
}

export fn main() Int {
	var xs = [1, 2, 3]
	rewrap(xs)
	return xs[0] - 1
}
// expect-error: MS3000 5:12 cannot move `xs` out of the function: the caller keeps ownership of a var parameter; return `xs.clone()` or change the value in place
