// conform: tags=diagnostics
// conform: phase=check
A := 1

fn f() Int {
	A = 2
	return A
}
// expect-error: MS3000 6:5 cannot assign to constant A; assignment targets are 'var' bindings and type fields
