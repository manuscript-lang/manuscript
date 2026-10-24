# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:51 TestInterfaceHintCorrectionsAndReceiverScope
type E:
    text: String

impl Error for E:
    fn message() ref String: self.text

fn error_value() Error: E("bad input")
