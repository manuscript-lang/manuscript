# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/list_take_drop_test.go:18 TestListTakeDropFaultLocations
export def main() -> Int:
    let copy = [1, 2].METHOD
    let part = copy(count: -7)
    return part.length()
