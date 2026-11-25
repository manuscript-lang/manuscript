// conform: tags=diagnostics
// conform: phase=check
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
// expect-error: MS2001 12:10 ambiguous alternative case X; qualify it with its type, e.g. Type.X
