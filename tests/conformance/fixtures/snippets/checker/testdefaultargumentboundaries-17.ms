// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:30 TestDefaultArgumentBoundaries
fn grow[T](value T, optional Int = grow(value: [value])) Int {
	return optional
}
// expect-error: MS3040 4:36 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
