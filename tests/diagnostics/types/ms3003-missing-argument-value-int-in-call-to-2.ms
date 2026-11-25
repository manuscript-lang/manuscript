// conform: tags=diagnostics
// conform: phase=check
fn f(m Map[Int, Int]) Void {
	m.add(1)
}
// expect-error: MS3003 4:7 missing argument value: Int in call to m.add; add 'value: <Int>'
