// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:19 TestRecursiveDataAndFiniteTypeApplications
type Node {
	next Node
}
// expect-exit: 0
