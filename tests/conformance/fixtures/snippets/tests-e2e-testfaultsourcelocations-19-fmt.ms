# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:153 TestFaultSourceLocations
def divide(value: Int) -> Int:
    return 1 / value

def outer(value: Int) -> Int:
    return value

export def main() -> Int:
    return outer(divide(0))
