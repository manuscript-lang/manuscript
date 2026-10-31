# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:24 TestInterfaceAndReceiverHints
type E:
    text: String

impl Error for E:
    fn message() String: this.text
