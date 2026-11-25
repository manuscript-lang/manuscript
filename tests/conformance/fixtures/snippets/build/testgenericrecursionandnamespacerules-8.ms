// conform: tags=control-flow,diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:271 TestGenericRecursionAndNamespaceRules
fn recurse[T](hold value T, count Int) &T {
	if count == 0 {
		return value
	}
	return recurse(value: value, count: count - 1)
}
// expect-exit: 0
