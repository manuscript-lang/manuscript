// conform: tags=diagnostics,lists,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/checker_test.go:91 TestNestedCollectionsPreserveFiniteRecursiveApplications
type Growing[T] {
	children List[Growing[List[T]]]
}
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in Growing.children; keep the same type arguments in the same positions along a recursive cycle
