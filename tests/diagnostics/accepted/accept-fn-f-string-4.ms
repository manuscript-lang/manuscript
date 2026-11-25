// conform: tags=diagnostics
// conform: phase=check
fn f() String {
	return "a}"
}
// expect-exit: 0
