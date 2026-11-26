// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	if true { return }
	return
}
// expect-exit: 0
