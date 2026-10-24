# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:26 TestInterfaceAndReceiverHints
def error_value() -> Error: Error.message("bad input")
