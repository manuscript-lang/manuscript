// conform: tags=diagnostics
// conform: phase=check
fn use(value Int?) Int {
	present := match value {
		n => n
		null => return 0
	}

	return match value {
		n => present + n
		null => 0
	}
}
// expect-exit: 0
