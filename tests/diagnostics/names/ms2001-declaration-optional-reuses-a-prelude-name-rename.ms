// conform: tags=diagnostics
// conform: phase=check
type Optional {
	x Int
}

fn f(o Int?) Int {
	return 0
}
// expect-error: MS2001 3:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
