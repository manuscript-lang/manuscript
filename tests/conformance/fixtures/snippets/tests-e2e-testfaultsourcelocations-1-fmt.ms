# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:16 TestFaultSourceLocations
def probe() -> Int:
    let values = [1, 2, 3]
    var sum = 9223372036854775807
    for x in values:
        sum += x
    return sum

export def main() -> Int:
    return probe()
