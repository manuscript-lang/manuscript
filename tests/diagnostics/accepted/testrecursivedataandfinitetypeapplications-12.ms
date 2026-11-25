// conform: tags=diagnostics,formatter,records,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:29 TestRecursiveDataAndFiniteTypeApplications
type Config {
	value Int!!
}
// expect-exit: 0
