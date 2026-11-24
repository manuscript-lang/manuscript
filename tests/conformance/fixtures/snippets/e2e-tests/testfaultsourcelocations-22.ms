// conform: tags=faults,generics,optional,tier-core
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:172 TestFaultSourceLocations
import panic from "@std/core.ms"

fn extract[T](move value T?) T {
	return value or panic("called Optional.get() on null")
}

export fn main() Int {
	return extract[Int](null)
}
