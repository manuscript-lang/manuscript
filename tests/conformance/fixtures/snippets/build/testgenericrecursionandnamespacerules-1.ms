// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:256 TestGenericRecursionAndNamespaceRules
fn recurse[T](value T) Void {
	recurse(value: [value])
}
