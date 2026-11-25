// conform: tags=diagnostics
// conform: phase=check
fn f() String {
	return "function() { return 1; }"
}
// expect-exit: 0
