// conform: tags=diagnostics,generics,lists,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:149
fn repeat[T](value T) Never {
	return repeat[T](value)  // Regular specialization; allowed.
}

fn grow[T](value T) Never {
	return grow[List[T]]([value])  // Rejected: expanding specialization.
}
// expect-error: MS3040 9:12 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
