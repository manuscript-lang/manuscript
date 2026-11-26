// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:17 TestEmptyFunctionDeclarations
type Options {
	count Int = 3
	total Int = count + 1
}
// expect-exit: 0
