# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:24 TestInterfaceAndReceiverHints
type E:
    text: String

impl Error for E:
    def message() -> String: this.text
