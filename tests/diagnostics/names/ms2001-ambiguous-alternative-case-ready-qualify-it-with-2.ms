// conform: tags=diagnostics
// conform: phase=check
enum First {
	Ready
}

enum Second {
	Ready
}

fn use(value Int?) Int {
	match value {
		ready => return Ready
		null => return 0
	}
}
// expect-error: MS2001 13:25 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
