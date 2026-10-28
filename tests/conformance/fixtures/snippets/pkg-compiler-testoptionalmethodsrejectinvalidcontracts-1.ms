# conform: tags=diagnostics,faults,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:62 TestOptionalMethodsRejectInvalidContracts
fn wrong(value: Optional[Int]) Int:
    return value.get("missing")
