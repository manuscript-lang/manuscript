// conform: tags=alternatives,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:20 TestRecursiveDataAndFiniteTypeApplications
enum A {
	End
	Next(value B)
}

type B {
	a A
}
// expect-exit: 0
