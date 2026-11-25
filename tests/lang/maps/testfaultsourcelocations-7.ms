// conform: tags=formatter,maps,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:80 TestFaultSourceLocations
fn crash() Int {
	return 1 / "".length()
}

export fn main() Int {
	var values = Map[Int, Int]()
	add := values.add
	add(value: crash(), key: 1)
	return values.length()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-7.ms:5 in crash
// expect-stderr:   at testfaultsourcelocations-7.ms:11 in main
