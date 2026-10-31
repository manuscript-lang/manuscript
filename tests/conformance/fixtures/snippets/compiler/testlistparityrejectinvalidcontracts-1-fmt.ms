# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_parity_test.go:15 TestListParityRejectInvalidContracts
fn wrong() Int:
    let values = [fn() Int: 1]
    return values.distinct().length()
