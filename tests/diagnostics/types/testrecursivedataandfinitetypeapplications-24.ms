// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:41 TestRecursiveDataAndFiniteTypeApplications
type Flip[T, U] {
	next Flip[U, T]
}
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in Flip.next; keep the same type arguments in the same positions along a recursive cycle
