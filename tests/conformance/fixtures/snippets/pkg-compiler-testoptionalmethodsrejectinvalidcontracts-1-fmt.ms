# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:62 TestOptionalMethodsRejectInvalidContracts
fn wrong(value: Int?) Int:
    return value.get("missing")
