// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/list_take_drop_test.go:18 TestListTakeDropFaultLocations
export fn main() Int:
    copy := [1, 2].METHOD
    part := copy(count: -7)
    return part.length()
