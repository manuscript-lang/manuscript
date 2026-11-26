// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:256 TestGenericRecursionAndNamespaceRules
fn recurse[T](value T) Void {
	recurse(value: [value])
}
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])
