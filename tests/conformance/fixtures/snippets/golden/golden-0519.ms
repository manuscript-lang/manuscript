// conform: tags=diagnostics
// conform: phase=check
type Options {
	required Int
	count Int = 1
}

fn f() Options => return Options()
