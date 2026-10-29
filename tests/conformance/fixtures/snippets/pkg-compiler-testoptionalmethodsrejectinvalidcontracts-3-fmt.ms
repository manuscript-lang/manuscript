# conform: tags=formatter,optional,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:68 TestOptionalMethodsRejectInvalidContracts
fn wrong(value: Result[Int, String]) Bool:
    return value.is_some()
