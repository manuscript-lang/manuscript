// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/control-flow/loops.md:102
fn count_down(start Int) Int {
	var remaining = start
	while remaining > 0 {
		remaining -= 1
	}
	return remaining
}
// expect-exit: 0
