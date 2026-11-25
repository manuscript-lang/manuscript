// conform: tags=diagnostics,mutation,strings,tier-core
// conform: phase=check
// conform: origin=design/proposals/reference-ownership.md
type User {
	name String
}

fn display(hold u User, anonymous Bool) String {
	if anonymous { return "anonymous" }
	return u.name
}

fn keep(u User) List[String] {
	return [display(u, false)]
}
// expect-error: MS3000 9:27 this function returns a reference into its arguments at 10:14 but a new value here; return `.clone()` of the part there, or build a new value on every path
