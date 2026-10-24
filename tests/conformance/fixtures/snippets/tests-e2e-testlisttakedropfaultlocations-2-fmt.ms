# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/list_take_drop_test.go:18 TestListTakeDropFaultLocations
export def main() -> Int:
    let copy = [1, 2].METHOD
    let part = copy(count: -7)
    return part.length()
