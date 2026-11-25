// conform: tags=diagnostics,formatter,lists,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:31 TestRecursiveDataAndFiniteTypeApplications
type Config {
	value List[Int?]?
}
// expect-exit: 0
