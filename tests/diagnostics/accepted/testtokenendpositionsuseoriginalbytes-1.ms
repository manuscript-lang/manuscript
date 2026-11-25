// conform: tags=diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/lexer_test.go:83 TestTokenEndPositionsUseOriginalBytes
fn f() String {
	return "é"  // keep
}
// expect-exit: 0
