// conform: tags=diagnostics
// conform: phase=check
fn later(letter String = f"{1 + 2}", interface_name Int = 1) Int {
	return 1
}
// expect-exit: 0
