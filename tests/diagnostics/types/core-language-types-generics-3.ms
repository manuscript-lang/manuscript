// conform: tags=diagnostics,generics,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:49
type Box[T] {
	value T
}

fn identity[T](value T) T {
	return value
}

fn same[T Equal](left T, right T) Bool {
	return left == right
}

box := Box[Int](1)
exact := identity[Int](1)
inferred := identity(1)
// expect-error: MS3070 16:8 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 17:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 18:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
