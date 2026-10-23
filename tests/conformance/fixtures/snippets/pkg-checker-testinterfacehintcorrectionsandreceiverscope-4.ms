# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:51 TestInterfaceHintCorrectionsAndReceiverScope
type E:
    text: String

impl Error for E:
    fn message() String: self.text

fn error_value() Error: E("bad input")
