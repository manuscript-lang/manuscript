// conform: tags=control-flow,diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:92
fn choose[T](first T, second T) T {
	return first
}

value := choose(1, 2)  // T = Int
// Rejected: conflicting evidence for T.
mixed := choose(1, 2.0)
// expect-error: MS3070 8:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 10:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
