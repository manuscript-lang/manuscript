// conform: tags=diagnostics
// conform: phase=check
fn value() Int {
	if true { return 3 }
	return 0
}
// expect-exit: 0
