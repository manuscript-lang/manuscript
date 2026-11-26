// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/partial_test.go:24 FuzzParsePartial
// 😀
fn read() Int {
	return 2
}
// expect-exit: 0
