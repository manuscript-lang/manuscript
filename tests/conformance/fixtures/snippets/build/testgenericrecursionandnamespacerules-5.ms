// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:260 TestGenericRecursionAndNamespaceRules
type Data {
	value Int
}

fn Data.compare() Void {
	return
}
// expect-exit: 0
