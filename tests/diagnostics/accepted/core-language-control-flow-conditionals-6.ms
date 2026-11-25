// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/control-flow/conditionals.md:73
fn nonnegative(value Int) Bool {
	if value < 0 {
		return false
	}
	return true
}
// expect-exit: 0
