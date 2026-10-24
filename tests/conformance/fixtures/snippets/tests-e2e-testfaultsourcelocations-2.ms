# conform: tags=control-flow,mutation,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:25 TestFaultSourceLocations
def probe() -> Int:
    var sum = 0
    var i = -9223372036854775808

    while i < -9223372036854775487:
        sum += i
        i += 1

    return sum

export def main() -> Int:
    return probe()
