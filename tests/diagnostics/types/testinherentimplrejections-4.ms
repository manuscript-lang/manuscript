// conform: tags=diagnostics,formatter,generics,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/inherent_methods_test.go:35 TestInherentImplRejections
type B[T] {
	x T
}

fn B.f() Int {
	return 1
}
// expect-error: MS3000 8:1 a method of B names one receiver argument per type parameter, as in 'fn B[T].name()'
