# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:25 TestInterfaceAndReceiverHints
def error_method() -> Unit:
    let method = Error.message
