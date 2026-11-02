# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:24 TestInterfaceAndReceiverHints
interface Named:
    fn name() String

type E:
    text: String

impl Named for E:
    fn name() String: this.text
