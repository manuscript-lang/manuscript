// conform: tags=diagnostics
// conform: phase=check
enum S {
	A
	B
	C
}

fn f(s S) Int {
	match s {
		A => {
			return 1
		}
	}

	return 0
}
// expect-error: MS3050 10:5 non-exhaustive match; missing cases: B, C, or add a final '_ => ...' arm; add the arms 'B => ...', 'C => ...'
