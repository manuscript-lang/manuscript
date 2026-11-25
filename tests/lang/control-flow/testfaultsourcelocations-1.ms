// conform: tags=control-flow,formatter,mutation,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:16 TestFaultSourceLocations
fn probe() Int {
	values := [1, 2, 3]
	var sum = 9223372036854775807
	for x in values {
		sum += x
	}
	return sum
}

export fn main() Int {
	return probe()
}
// expect-exit: 134
// expect-stderr: Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt
// expect-stderr:   at testfaultsourcelocations-1.ms:8 in probe
// expect-stderr:   at testfaultsourcelocations-1.ms:14 in main
