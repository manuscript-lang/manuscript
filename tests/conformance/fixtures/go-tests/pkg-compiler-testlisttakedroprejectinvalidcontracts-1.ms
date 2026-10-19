# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/list_take_drop_test.go:14 TestListTakeDropRejectInvalidContracts
fn wrong() List[Int]:
    let copy = [1].METHOD
    return copy(length: 1)
