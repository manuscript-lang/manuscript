// conform: tags=formatter,maps,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:74 TestFaultSourceLocations
fn crash() Int {
	return 1 / "".length()
}

export fn main() Int {
	var values = Map[Int, Int]()
	values.add(crash(), 1)
	return values.length()
}
