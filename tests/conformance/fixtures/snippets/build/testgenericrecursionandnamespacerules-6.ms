// conform: tags=alternatives,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:261 TestGenericRecursionAndNamespaceRules
enum First {
	Ready(value Int)
}

enum Second {
	Ready(value Int)
}

fn wrong() First {
	return Ready(value: 1)
}
// expect-error: MS2001 13:12 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
