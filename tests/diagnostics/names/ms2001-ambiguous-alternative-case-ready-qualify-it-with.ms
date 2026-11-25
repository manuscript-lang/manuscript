// conform: tags=diagnostics
// conform: phase=check
enum First {
	Ready(value Int)
}

enum Second {
	Ready(value Int)
}

fn wrong() First {
	return Ready(value: 1)
}
// expect-error: MS2001 12:12 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
