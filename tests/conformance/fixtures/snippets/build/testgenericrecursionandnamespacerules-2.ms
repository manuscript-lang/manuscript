// conform: tags=diagnostics,generics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:257 TestGenericRecursionAndNamespaceRules
fn recurse[T](value T) Void {
	next := recurse[List[T]]
}
// expect-error: MS3040 5:13 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
