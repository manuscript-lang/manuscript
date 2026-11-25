// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/inspect_locals_test.go:11 TestLocalMetadataIsDeterministic
fn answer(input Int) Int {
	value := input
	return value
}
// expect-exit: 0
