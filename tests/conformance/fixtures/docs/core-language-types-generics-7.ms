// conform: tags=diagnostics,generics,lists,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:115
fn count[T](values List[T]) Int {
	return 0
}

known := count[Int]([])
// Rejected: the empty list does not determine T.
unknown := count([])
// expect-error: MS3070 8:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 10:12 a constant takes literals, operators, collections, and other constants; compute this value in a function
