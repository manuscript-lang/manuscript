// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:42 TestRecursiveDataAndFiniteTypeApplications
type Grow[T] {
	next Bridge
}

type Bridge {
	next Grow[Int]
}
// expect-error: MS3040 9:5 recursive generic applications must preserve their parameters in Bridge.next; keep the same type arguments in the same positions along a recursive cycle
