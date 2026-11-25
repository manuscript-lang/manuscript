// conform: tags=diagnostics
// conform: phase=check
A := 1

fn f() Int {
	return A()
}
// expect-error: MS3000 6:12 A is a constant, not a function; remove the parentheses and write A
