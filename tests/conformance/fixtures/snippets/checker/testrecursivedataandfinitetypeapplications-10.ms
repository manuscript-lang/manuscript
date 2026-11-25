// conform: tags=diagnostics,formatter,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:27 TestRecursiveDataAndFiniteTypeApplications
type Config {
	value Int??
}
// expect-exit: 0
