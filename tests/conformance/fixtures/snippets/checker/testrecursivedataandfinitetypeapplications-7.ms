// conform: tags=diagnostics,lists,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:24 TestRecursiveDataAndFiniteTypeApplications
type Phantom[T] {
	value Int
}

type Grow[T] {
	value Phantom[Grow[List[T]]]
}
// expect-error: MS3040 9:5 recursive generic applications must preserve their parameters in Grow.value; keep the same type arguments in the same positions along a recursive cycle
