// conform: tags=diagnostics,numbers,faults,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	return 1 / 0
}
// expect-error: MS3000 5:14 division by zero always faults; guard the divisor or use a nonzero constant
