# conform: tags=faults,formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:172 TestFaultSourceLocations
def extract[T](value: Optional[T]) -> T:
    return value.get()

export def main() -> Int:
    return extract[Int](none)
