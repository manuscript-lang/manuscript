// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/ambiguous_case_test.go:17 TestAmbiguousCaseReportsOnce
enum A {
	X(n Int)
}

enum B {
	X(n Int)
}

fn f() Int {
	a := X(n: 1)
	return 1
}
// expect-error: MS2001 13:10 ambiguous alternative case X; qualify it with its type, e.g. Type.X
