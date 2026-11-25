// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:145
fn incomplete(active Bool) Int {
	if active {
		return 1
	}
	// Rejected: the false path reaches the end without returning Int.
}
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
