// conform: tags=faults,formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:172 TestFaultSourceLocations
import panic from "@std/core.ms"

fn extract[T](value: T?) T:
	return value or panic("called Optional.get() on null")

export fn main() Int:
	return extract[Int](null)
