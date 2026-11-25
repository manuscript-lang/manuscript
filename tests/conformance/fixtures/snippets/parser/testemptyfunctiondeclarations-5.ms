// conform: tags=diagnostics,formatter,interfaces,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:15 TestEmptyFunctionDeclarations
interface Read {
	fn read(limit Int?) Int
}
// expect-exit: 0
