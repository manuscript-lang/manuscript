// conform: tags=diagnostics
// conform: phase=check
fn f(command String) Int {
	match command {
		"réport" => return 1
	}

	return 0
}
// expect-error: MS3050 4:5 non-exhaustive match on String; add a final '_ => ...' arm
