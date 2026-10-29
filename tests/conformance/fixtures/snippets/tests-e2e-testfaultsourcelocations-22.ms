# conform: tags=faults,generics,optional,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:172 TestFaultSourceLocations
fn extract[T](value: Optional[T]) ref T:
    return value.get()

export fn main() Int:
    return extract[Int](none)
