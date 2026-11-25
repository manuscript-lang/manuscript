// conform: tags=diagnostics
// conform: phase=check
fn g(a Int) Int {
	return a
}

fn f() Int {
	return g()
}
// expect-error: MS3003 8:12 missing argument a: Int in call to g; add 'a: <Int>'
