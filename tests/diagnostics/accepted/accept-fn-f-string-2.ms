// conform: tags=diagnostics
// conform: phase=check
fn f() String {
	return "a { b"
}
// expect-exit: 0
