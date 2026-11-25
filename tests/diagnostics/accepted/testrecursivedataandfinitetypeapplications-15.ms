// conform: tags=closures,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:32 TestRecursiveDataAndFiniteTypeApplications
type Node[T] {
	build fn() Node[T]
}
// expect-exit: 0
