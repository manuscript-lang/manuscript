// conform: tags=diagnostics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=tests/e2e/inherent_methods_test.go:36 TestInherentImplRejections
type B {
	x Int
}

fn B.m[U](u U) &U {
	return u
}
// expect-error: MS3000 8:6 a `&` result points into an argument; mark that argument `hold`, or return an owned value
