# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:47 TestInterfaceHintCorrectionsAndReceiverScope
interface Shape:
    def area() -> Int

type Sq:
    s: Int

impl Shape for Sq:
    def area() -> Int: self.s * self.s
