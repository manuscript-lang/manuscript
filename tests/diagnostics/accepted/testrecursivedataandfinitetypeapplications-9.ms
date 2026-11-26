// conform: tags=diagnostics,formatter,optional,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:26 TestRecursiveDataAndFiniteTypeApplications
type Entry {
	name String
	nickname String?
}

type Person {
	primary Entry?
}
// expect-exit: 0
