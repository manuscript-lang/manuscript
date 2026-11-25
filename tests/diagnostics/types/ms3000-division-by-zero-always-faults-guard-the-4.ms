// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	crash := fn() Int {
		return 1 / 0
	}
	return crash()
}
// expect-error: MS3000 5:18 division by zero always faults; guard the divisor or use a nonzero constant
