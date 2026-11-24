// conform: tags=control-flow,diagnostics,tier-core,scope-cleanup
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:204 TestInlineSuites
fn f() Void {
	while true { break }
	for x in values { consume(x) }
}
