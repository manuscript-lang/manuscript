// conform: tags=formatter,maps,strings,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:118 TestFaultSourceLocations
fn crash(key String, value Int) Bool {
	return 1 / value == 0
}

export fn main() Int {
	value Map[String, Int] := {"a": 0}
	return value.filter(crash).length()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-13.ms:5 in crash
// expect-stderr:   at @std/collections/collections.ms:<LINE> in Map.filter
// expect-stderr:   at testfaultsourcelocations-13.ms:10 in main
