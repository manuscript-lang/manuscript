# conform: tags=diagnostics,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:68 TestOptionalMethodsRejectInvalidContracts
def wrong(value: Result[Int, String]) -> Bool:
    return value.is_some()
