// conform: tags=diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:14 TestEmptyFunctionDeclarations
type Counter {
	value Int
}

fn Counter.double() Int {
	return self.value * 2
}
// expect-exit: 0
