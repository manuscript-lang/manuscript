// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:60 FuzzParse
type Item {
	value Int
}
// expect-exit: 0
