// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/partial_continuation_test.go:93 TestPartialContinuationDifferential
fn later(value Int = 3) Int {
	return value
}
// expect-exit: 0
