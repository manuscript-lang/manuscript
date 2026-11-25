// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:60 FuzzParse
fn f() Void {
	return
}
// expect-exit: 0
