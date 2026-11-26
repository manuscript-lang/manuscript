// conform: tags=diagnostics,formatter,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:36 TestRecursiveDataAndFiniteTypeApplications
type A[T] {
	b B[List[T]]
}

type B[U] {
	a A[U]
}
// expect-error: MS3040 9:5 recursive generic applications must preserve their parameters in B.a; keep the same type arguments in the same positions along a recursive cycle
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in A.b; keep the same type arguments in the same positions along a recursive cycle
