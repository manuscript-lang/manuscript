// conform: tags=diagnostics
// conform: phase=check
fn answer() Int {
	number := 42
	return number
}

fn later() Int {
	return 2
}
// expect-exit: 0
