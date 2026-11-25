// conform: phase=check
// conform: tags=alternatives,diagnostics,match,tier-core
enum Outcome {
	Success(value Int)
	Failure
}

fn value(outcome Outcome) Int {
	return match outcome {
		Success(number) => number
	}
}
// expect-error: MS3050 9:12 non-exhaustive match; missing cases: Failure, or add a final '_ => ...' arm; add the arms 'Failure => ...'
