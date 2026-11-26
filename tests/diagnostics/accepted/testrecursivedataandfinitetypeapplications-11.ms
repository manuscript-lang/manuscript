// conform: tags=alternatives,diagnostics,formatter,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:28 TestRecursiveDataAndFiniteTypeApplications
enum Config {
	Value(value Int??)
}
// expect-exit: 0
