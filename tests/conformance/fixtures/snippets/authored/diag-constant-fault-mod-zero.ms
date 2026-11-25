// conform: tags=diagnostics,numbers,faults,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int {
	return 7 % (2 - 2)
}
// expect-error: MS3000 5:14 division by zero always faults; guard the divisor or use a nonzero constant
