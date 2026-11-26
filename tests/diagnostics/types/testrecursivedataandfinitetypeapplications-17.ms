// conform: tags=diagnostics,formatter,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:34 TestRecursiveDataAndFiniteTypeApplications
type Grow[T] {
	next Grow[List[T]]
}
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in Grow.next; keep the same type arguments in the same positions along a recursive cycle
