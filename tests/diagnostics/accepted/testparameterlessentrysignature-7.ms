// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:211 TestParameterlessEntrySignature
fn helper() Int {
	return 0
}
// expect-exit: 0
