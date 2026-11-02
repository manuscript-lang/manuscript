# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:25 TestInterfaceAndReceiverHints
fn error_method() Unit:
    let method = Error.message
