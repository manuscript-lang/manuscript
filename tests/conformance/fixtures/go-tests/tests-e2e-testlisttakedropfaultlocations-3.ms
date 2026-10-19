# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=tests/e2e/list_take_drop_test.go:23 TestListTakeDropFaultLocations
export fn main() Int:
    let empty: List[Int] = []
    let part = empty.METHOD(-7)
    return part.length()
