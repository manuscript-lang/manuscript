# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:65 TestOptionalMethodsRejectInvalidContracts
fn wrong(value: Optional[Optional[Int]]) Int:
    return value.get()
