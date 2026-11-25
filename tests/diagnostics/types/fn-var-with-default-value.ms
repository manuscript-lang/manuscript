// conform: tags=testing,tier-core
// conform: phase=check
fn push(var values List[Int], value Int = 1) Void {
	values.append(value)
}

export fn main() Int {
	var values List[Int] = []

	// A function value fills defaults in a thunk that cannot also pass a var parameter.
	change := push
	change(values, 2)
	return values.length() - 1
}
// expect-error: MS3000 11:15 push has both a var parameter and a parameter default, so it cannot be a function value; call push from a closure that supplies the default
