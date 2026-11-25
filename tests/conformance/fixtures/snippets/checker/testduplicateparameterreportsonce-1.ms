// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/duplicate_parameter_test.go:15 TestDuplicateParameterReportsOnce
fn f(a Int, a Int) Int {
	return a
}
// expect-error: MS3000 4:13 duplicate parameter or field a; each name may appear once, so rename one
