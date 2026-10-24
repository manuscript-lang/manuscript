# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:147 TestFaultSourceLocations
def zero() -> Int:
    return 0

export def main() -> Int:
    return (1 / zero())
