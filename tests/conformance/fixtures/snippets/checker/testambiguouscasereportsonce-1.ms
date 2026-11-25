// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/ambiguous_case_test.go:16 TestAmbiguousCaseReportsOnce
enum A {
	X
}

enum B {
	X
}

fn f() Int {
	a := X
	return 1
}
// expect-error: MS2001 13:10 ambiguous alternative case X; qualify it with its type, e.g. Type.X
