// conform: tags=diagnostics
// conform: phase=check
enum Flag {
	Ready
}

fn use(value Int?) Int {
	match value {
		ready => return Ready
		null => return 0
	}
}
// expect-error: MS3001 9:25 expected Int, found Flag (in the return value)
