// conform: tags=closures,formatter,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export fn main() Int {
	crash := fn() Int {
		return 1 / "".length()
	}
	return crash()
}
