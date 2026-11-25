// conform: tags=diagnostics,formatter,generics,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:33 TestRecursiveDataAndFiniteTypeApplications
interface Node[T] {
	fn build() Node[T]
}
// expect-exit: 0
