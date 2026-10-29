# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_take_drop_test.go:14 TestListTakeDropRejectInvalidContracts
fn wrong() List[Int]:
    let copy = [1].METHOD
    return copy(length: 1)
