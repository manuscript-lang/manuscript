// conform: tags=diagnostics,generics,interfaces,lists,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:39 TestRecursiveDataAndFiniteTypeApplications
interface Grow[T] {
	fn next() Grow[List[T]]
}
// expect-error: MS3040 5:8 recursive generic applications must preserve their parameters in Grow.next; keep the same type arguments in the same positions along a recursive cycle
