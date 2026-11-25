// conform: tags=diagnostics
// conform: phase=check
type Outcome {
	value Int
}

fn caller() Void {
	Outcome(1)
}
// expect-exit: 0
