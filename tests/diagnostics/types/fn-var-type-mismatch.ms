// conform: tags=testing,tier-core
// conform: phase=check
fn append_one(var values List[Int]) Int {
	values.append(1)
	return values.length()
}

export fn main() Int {
	// `fn(var List[Int]) Int` is not `fn(List[Int]) Int`: a function that changes its parameter
	// cannot stand in for one that only reads it (the other direction is accepted).
	read fn(List[Int]) Int := append_one
	return read([1]) - 2
}
// expect-error: MS3001 11:31 expected fn(List[Int]) Int, found fn(var List[Int]) Int (in the initializer of 'read')
