// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	return 1
}

X := f
// expect-error: MS3000 7:6 a constant can refer only to other constants, but f is a function; compute the value in a function
