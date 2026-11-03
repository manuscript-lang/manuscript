# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:51 TestInterfaceHintCorrectionsAndReceiverScope
interface Named:
    fn name() String

type E:
    text: String

impl Named for E:
    fn name() String: self.text.clone()

fn named_value() Named: E("bad input")
