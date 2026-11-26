// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/duplicate_parameter_test.go:16 TestDuplicateParameterReportsOnce
fn f() Int {
	g := fn(a Int, a Int) Int => return a
	return 1
}
// expect-format: rewritten
// expect-formatted: fn f() Int {
// expect-formatted: \tg := fn(a, a Int) Int => return a
// expect-formatted: \treturn 1
// expect-formatted: }
