// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/defaults_test.go:105 TestPositionalCallNeedsNoLabelDiagnostic
fn f(a Int, b Int) Int {
	return a + b
}

fn call() Int {
	return f(1, 2)
}
// expect-format: rewritten
// expect-formatted: fn f(a, b Int) Int {
// expect-formatted: \treturn a + b
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn call() Int {
// expect-formatted: \treturn f(1, 2)
// expect-formatted: }
