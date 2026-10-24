# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_parity_test.go:15 TestListParityRejectInvalidContracts
def wrong() -> Int:
    let values = [lambda () -> Int: 1]
    return values.distinct().length()
