// conform: tags=control-flow,faults,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:35 TestFaultSourceLocations

fn checked(n Int) Int!Error {
	if n < 0 {
		return error(Error("negative"))
	}
	return ok(n + 1)
}

fn chain(n Int) Int!Error {
	value := checked(n)?
	return ok(value)
}

export fn main() Int {
	return chain(9223372036854775807).get()
}
// expect-exit: 134
// expect-stderr: Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt
// expect-stderr:   at testfaultsourcelocations-3.ms:9 in checked
// expect-stderr:   at testfaultsourcelocations-3.ms:13 in chain
// expect-stderr:   at testfaultsourcelocations-3.ms:18 in main
