// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	return 1
}

X := f()
// expect-error: MS3070 7:6 a constant takes literals, operators, collections, and other constants; compute this value in a function
