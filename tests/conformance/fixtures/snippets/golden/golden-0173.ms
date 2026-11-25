// conform: tags=diagnostics
// conform: phase=check
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
// expect-error: MS2001 12:10 ambiguous alternative case X; qualify it with its type, e.g. Type.X
