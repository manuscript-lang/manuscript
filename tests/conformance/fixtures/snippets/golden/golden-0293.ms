// conform: tags=diagnostics
// conform: phase=check
enum S {
	A
	B
}

fn f(s S) Int {
	match s {
		A => {
			return 1
		}
		other => {
			return 2
		}
	}
}
// expect-error: MS2001 13:9 'other' is not a case of S; a lone lowercase name binds an Optional's payload, but this is not an Optional; use '_' for a catch-all arm, or one of the cases: A, B
