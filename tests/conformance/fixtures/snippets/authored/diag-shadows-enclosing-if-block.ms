// conform: tags=diagnostics,control-flow,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	x := 1

	if x > 0 {
		x := 2
		return x
	}

	return 0
}
// expect-error: MS3000 8:9 binding x shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'
