// conform: tags=diagnostics
// conform: phase=check
fn f(r Result[Int?, String]) Int {
	match r {
		ok(n) => return n
	}

	return 0
}
// expect-error: MS3001 5:25 expected Int, found Int? (in the return value); Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
// expect-error: MS3050 4:5 non-exhaustive match; missing cases: error, or add a final '_ => ...' arm; add the arms 'error(cause) => ...'
