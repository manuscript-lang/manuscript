// conform: tags=diagnostics
// conform: phase=check
type Growing[T] {
	value T
	next Int = grow([value])
}

fn grow[T](value T) Int {
	item := Growing(value: value)
	return 0
}
// expect-error: MS3040 9:13 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
// expect-error: MS3040 5:16 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
