// conform: tags=faults,formatter,generics,optional,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:172 TestFaultSourceLocations
import panic from "@std/core.ms"

fn extract[T](move value T?) T {
	return value or panic("called Optional.get() on null")
}

export fn main() Int {
	return extract[Int](null)
}
// expect-exit: 134
// expect-stderr: called Optional.get() on null
// expect-stderr:   at testfaultsourcelocations-22.ms:7 in extract
// expect-stderr:   at testfaultsourcelocations-22.ms:11 in main
