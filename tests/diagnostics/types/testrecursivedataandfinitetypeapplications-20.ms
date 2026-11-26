// conform: tags=closures,diagnostics,formatter,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:37 TestRecursiveDataAndFiniteTypeApplications
type Grow[T] {
	next fn() Grow[List[T]]
}
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in Grow.next; keep the same type arguments in the same positions along a recursive cycle
