# conform: tags=diagnostics,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:68 TestOptionalMethodsRejectInvalidContracts
fn wrong(value: Int!String) Bool:
    return value.is_some()
