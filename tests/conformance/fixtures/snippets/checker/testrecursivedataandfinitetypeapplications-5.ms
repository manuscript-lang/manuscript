// conform: tags=diagnostics,formatter,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:22 TestRecursiveDataAndFiniteTypeApplications
type A[T] {
	value T
	b B[T]?
}

type B[U] {
	a A[U]
}
// expect-exit: 0
