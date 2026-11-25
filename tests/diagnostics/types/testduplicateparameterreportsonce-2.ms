// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/duplicate_parameter_test.go:16 TestDuplicateParameterReportsOnce
fn f() Int {
	g := fn(a Int, a Int) Int => return a
	return 1
}
// expect-error: MS3000 5:20 duplicate parameter or field a; each name may appear once, so rename one
